import AVFoundation
import Foundation
import Speech

final class SpeechController {
    private let recognizer = SFSpeechRecognizer(locale: Locale.current)
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var tapInstalled = false
    private var stopCompletion: ((String) -> Void)?
    private var sessionID = UUID()
    private var activationID = UUID()
    private(set) var transcript = ""

    func start(onTranscript: @escaping (String) -> Void,
               onLevel: @escaping (Double) -> Void,
               onFailure: @escaping (String) -> Void) {
        let requestedActivation = UUID()
        activationID = requestedActivation
        requestPermissions { [weak self] allowed in
            DispatchQueue.main.async {
                guard let self, self.activationID == requestedActivation else { return }
                guard allowed else {
                    onFailure("Microphone and Speech Recognition permissions are required.")
                    return
                }
                do { try self.begin(onTranscript: onTranscript, onLevel: onLevel, onFailure: onFailure) }
                catch { onFailure(error.localizedDescription) }
            }
        }
    }

    func stop(completion: @escaping (String) -> Void) {
        activationID = UUID()
        if audioEngine.isRunning { audioEngine.stop() }
        removeTapIfNeeded()
        stopCompletion = completion
        request?.endAudio()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.completeStop()
        }
    }

    func cancel() {
        activationID = UUID()
        sessionID = UUID()
        if audioEngine.isRunning { audioEngine.stop() }
        removeTapIfNeeded()
        task?.cancel(); task = nil; request = nil; transcript = ""; stopCompletion = nil
    }

    private func completeStop() {
        guard let completion = stopCompletion else { return }
        stopCompletion = nil
        sessionID = UUID()
        task?.cancel(); task = nil; request = nil
        completion(transcript.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func begin(onTranscript: @escaping (String) -> Void,
                       onLevel: @escaping (Double) -> Void,
                       onFailure: @escaping (String) -> Void) throws {
        cancel()
        transcript = ""
        guard let recognizer, recognizer.isAvailable else {
            throw NotchError.unavailable("macOS Speech Recognition is unavailable right now.")
        }
        let activeSession = sessionID
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        self.request = request

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            DispatchQueue.main.async {
                guard self?.sessionID == activeSession else { return }
                if let result {
                    self?.transcript = result.bestTranscription.formattedString
                    onTranscript(result.bestTranscription.formattedString)
                    if result.isFinal { self?.completeStop() }
                }
                if let error, self?.audioEngine.isRunning == true { onFailure(error.localizedDescription) }
            }
        }

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw NotchError.unavailable("No microphone input is available.") }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
            guard let data = buffer.floatChannelData?[0] else { return }
            let count = Int(buffer.frameLength)
            guard count > 0 else { return }
            var sum: Float = 0
            for index in 0..<count { sum += data[index] * data[index] }
            let rms = sqrt(sum / Float(count))
            let normalized = min(1, max(0, (Double(rms) - 0.008) * 14))
            DispatchQueue.main.async { onLevel(normalized) }
        }
        tapInstalled = true
        audioEngine.prepare()
        try audioEngine.start()
    }

    private func removeTapIfNeeded() {
        guard tapInstalled else { return }
        audioEngine.inputNode.removeTap(onBus: 0)
        tapInstalled = false
    }

    private func requestPermissions(completion: @escaping (Bool) -> Void) {
        let speech: (@escaping (Bool) -> Void) -> Void = { next in
            switch SFSpeechRecognizer.authorizationStatus() {
            case .authorized: next(true)
            case .notDetermined:
                SFSpeechRecognizer.requestAuthorization { next($0 == .authorized) }
            default: next(false)
            }
        }
        speech { speechAllowed in
            guard speechAllowed else { completion(false); return }
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized: completion(true)
            case .notDetermined: AVCaptureDevice.requestAccess(for: .audio, completionHandler: completion)
            default: completion(false)
            }
        }
    }
}
