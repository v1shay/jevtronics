import AVFoundation
import Foundation

/// Plays a locally installed Piper ONNX voice without a speech service or app-bundled model.
@MainActor
final class SpokenResponse {
    private let enabledKey = "spokenResponsesEnabled"
    private let voicePathKey = "spokenResponseONNXPath"
    private let voiceDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
    private var process: Process?
    private var player: AVAudioPlayer?
    private var outputFile: URL?
    private var requestID = UUID()
    private var failureHandler: ((String) -> Void)?
    private(set) var lastError: String?
    private(set) var lastAudioBytes = 0

    var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: enabledKey)
            if !newValue { stop() }
        }
    }

    var availableVoices: [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: voiceDirectory, includingPropertiesForKeys: nil
        )) ?? []
        var voices = files.filter { $0.pathExtension.lowercased() == "onnx" && Self.hasConfig(for: $0) }
        if let selected = UserDefaults.standard.string(forKey: voicePathKey) {
            let custom = URL(fileURLWithPath: selected)
            if FileManager.default.fileExists(atPath: custom.path), Self.hasConfig(for: custom),
               !voices.contains(where: { $0.path == custom.path }) {
                voices.append(custom)
            }
        }
        return voices.sorted {
            let leftJarvis = $0.lastPathComponent.lowercased().contains("jarvis")
            let rightJarvis = $1.lastPathComponent.lowercased().contains("jarvis")
            return leftJarvis == rightJarvis
                ? $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending
                : leftJarvis
        }
    }

    var selectedVoiceURL: URL? {
        if let saved = UserDefaults.standard.string(forKey: voicePathKey) {
            let voice = URL(fileURLWithPath: saved)
            if FileManager.default.fileExists(atPath: voice.path), Self.hasConfig(for: voice) { return voice }
        }
        return availableVoices.first
    }

    func selectVoice(_ url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path), Self.hasConfig(for: url) else { return false }
        UserDefaults.standard.set(url.path, forKey: voicePathKey)
        stop()
        return true
    }

    func speak(_ response: String, force: Bool = false, onFailure: ((String) -> Void)? = nil) {
        guard isEnabled || force else { return }
        let text = Self.concise(response)
        guard !text.isEmpty else { return }
        stop()
        failureHandler = onFailure
        lastAudioBytes = 0
        guard let voice = selectedVoiceURL, let executable = Self.piperExecutable else {
            fail("Jarvis ONNX voice or Piper is unavailable. Check the ONNX Voice menu.")
            return
        }

        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("jev-notch-tts-\(UUID().uuidString).wav")
        let runID = requestID
        let process = Process()
        let input = Pipe()
        process.executableURL = executable
        process.arguments = ["--model", voice.path, "--config", Self.configURL(for: voice).path,
                             "--output-file", output.path]
        process.standardInput = input
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { [weak self] completed in
            DispatchQueue.main.async { [weak self] in
                self?.finish(runID: runID, status: completed.terminationStatus, output: output)
            }
        }
        do {
            try process.run()
            self.process = process
            outputFile = output
            try input.fileHandleForWriting.write(contentsOf: Data((text + "\n").utf8))
            try input.fileHandleForWriting.close()
            lastError = nil
        } catch {
            if process.isRunning { process.terminate() }
            self.process = nil
            outputFile = nil
            try? FileManager.default.removeItem(at: output)
            fail("Piper could not start: \(error.localizedDescription)")
        }
    }

    func stop() {
        requestID = UUID()
        if let process, process.isRunning { process.terminate() }
        process = nil
        player?.stop()
        player = nil
        failureHandler = nil
        if let outputFile { try? FileManager.default.removeItem(at: outputFile) }
        outputFile = nil
    }

    private func finish(runID: UUID, status: Int32, output: URL) {
        defer { try? FileManager.default.removeItem(at: output) }
        guard runID == requestID else { return }
        process = nil
        outputFile = nil
        guard status == 0, let audio = try? Data(contentsOf: output), audio.count > 44 else {
            fail("Piper could not synthesize the selected ONNX voice.")
            return
        }
        do {
            let player = try AVAudioPlayer(data: audio)
            player.prepareToPlay()
            guard player.play() else {
                fail("macOS could not play the synthesized audio.")
                return
            }
            self.player = player
            lastAudioBytes = audio.count
            lastError = nil
        } catch {
            fail("macOS could not open Piper audio: \(error.localizedDescription)")
        }
    }

    private func fail(_ message: String) {
        lastError = message
        failureHandler?(message)
    }

    private static func hasConfig(for voice: URL) -> Bool {
        FileManager.default.fileExists(atPath: configURL(for: voice).path)
    }

    private static func configURL(for voice: URL) -> URL {
        URL(fileURLWithPath: voice.path + ".json")
    }

    private static var piperExecutable: URL? {
        let pathEntries = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":").map { String($0) + "/piper" }
        let candidates = ["/opt/anaconda3/bin/piper", "/opt/homebrew/bin/piper", "/usr/local/bin/piper"] + pathEntries
        return candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) })
            .map { URL(fileURLWithPath: $0) }
    }

    static func displayName(for voice: URL) -> String {
        voice.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "en_US-", with: "")
            .replacingOccurrences(of: "-medium", with: "")
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }

    static func concise(_ response: String) -> String {
        let flattened = response.replacingOccurrences(of: "\n", with: ". ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard flattened.count > 280 else { return flattened }
        let prefix = String(flattened.prefix(280))
        if let boundary = prefix.lastIndex(of: " ") { return String(prefix[..<boundary]) + "." }
        return prefix + "."
    }
}
