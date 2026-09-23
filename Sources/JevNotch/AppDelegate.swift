import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NotchPanelDelegate {
    private let speech = SpeechController()
    private let spokenResponse = SpokenResponse()
    private let jev = JevClient()
    private let engine = ToolEngine()
    private lazy var workflow = WorkflowCoordinator(jev: jev, engine: engine)
    private var panel: NotchPanelController!
    private var globalMonitors: [Any] = []
    private var localMonitor: Any?
    private var holdTimer: Timer?
    private var workflowTask: Task<Void, Never>?
    private var isListening = false
    private var commandDown = false
    private var shortcutUsed = false
    private var commandPressedAt: TimeInterval?
    private var lastQuickCommandReleaseAt: TimeInterval?
    private var suppressCommandRelease = false
    private var currentTranscript = ""
    private var pending: PendingWorkflow?
    private var requestTelemetry: RequestTelemetry?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        panel = NotchPanelController()
        panel.delegate = self
        panel.show()
        installMenuBarItem()
        installCommandHoldMonitor()
        Task { await engine.prewarmTextModel() }
        _ = SystemContext.accessibilityTrusted(prompt: false)
        if ProcessInfo.processInfo.environment["JEV_NOTCH_PREVIEW"] == "1" {
            panel.update(.init(phase: .routing, transcript: "Open the project dashboard", detail: "Jev is selecting a typed tool…", level: 0.55, expanded: true, tool: "Open application", confidence: 0.93))
        } else {
            panel.update(.init(phase: .idle, detail: "Hold Command to speak", expanded: false))
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        globalMonitors.forEach(NSEvent.removeMonitor)
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        speech.cancel()
        spokenResponse.stop()
    }

    private func installCommandHoldMonitor() {
        if let flags = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: { [weak self] in self?.handleFlags($0) }) { globalMonitors.append(flags) }
        if let keys = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { [weak self] _ in self?.shortcutUsed = true; self?.holdTimer?.invalidate() }) { globalMonitors.append(keys) }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
            if event.type == .flagsChanged { self?.handleFlags(event) }
            else { self?.shortcutUsed = true; self?.holdTimer?.invalidate() }
            return event
        }
    }

    private func handleFlags(_ event: NSEvent) {
        let down = event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command)
        guard down != commandDown else { return }
        commandDown = down
        let now = ProcessInfo.processInfo.systemUptime
        if down {
            if let lastRelease = lastQuickCommandReleaseAt, now - lastRelease <= 0.42 {
                lastQuickCommandReleaseAt = nil
                suppressCommandRelease = true
                shortcutUsed = true
                holdTimer?.invalidate(); holdTimer = nil
                cancelVoiceSession()
                return
            }
            commandPressedAt = now
            shortcutUsed = false
            holdTimer?.invalidate()
            holdTimer = Timer.scheduledTimer(timeInterval: 1.0, target: self, selector: #selector(commandHoldDidFire), userInfo: nil, repeats: false)
        } else {
            holdTimer?.invalidate(); holdTimer = nil
            if suppressCommandRelease {
                suppressCommandRelease = false
                commandPressedAt = nil
                return
            }
            if isListening {
                lastQuickCommandReleaseAt = nil
                finishListening()
            } else if !shortcutUsed, let pressedAt = commandPressedAt, now - pressedAt < 0.65 {
                lastQuickCommandReleaseAt = now
            } else {
                lastQuickCommandReleaseAt = nil
            }
            commandPressedAt = nil
        }
    }

    @objc private func commandHoldDidFire() {
        guard commandDown, !shortcutUsed else { return }
        beginListening()
    }

    private func beginListening() {
        guard !isListening, pending == nil else { return }
        spokenResponse.stop()
        isListening = true; currentTranscript = ""
        requestTelemetry = nil
        panel.show()
        panel.update(.init(phase: .listening, detail: "Release Command to run", level: 0, expanded: true))
        speech.start(
            onTranscript: { [weak self] text in
                guard let self else { return }
                self.currentTranscript = text
                self.panel.update(.init(phase: .listening, transcript: text, detail: "Release Command to run", level: 0.45, expanded: true))
            },
            onLevel: { [weak self] level in
                guard let self else { return }
                self.panel.update(.init(phase: .listening, transcript: self.currentTranscript, detail: "Release Command to run", level: level, expanded: true))
            },
            onFailure: { [weak self] message in self?.showFailure(message) }
        )
    }

    private func finishListening() {
        isListening = false
        requestTelemetry = RequestTelemetry()
        panel.update(.init(phase: .routing, transcript: currentTranscript, detail: "Jev is selecting a typed tool…", expanded: true))
        speech.stop { [weak self] transcript in
            guard let self else { return }
            guard !transcript.isEmpty else { self.showFailure("I didn't hear a command."); return }
            self.currentTranscript = transcript
            self.route(transcript)
        }
    }

    private func route(_ transcript: String) {
        panel.update(.init(phase: .routing, transcript: transcript, detail: "Jev is selecting a typed tool…", expanded: true))
        let context = SystemContext.snapshot()
        let telemetry = requestTelemetry ?? RequestTelemetry()
        requestTelemetry = telemetry
        workflowTask?.cancel()
        workflowTask = Task {
            let outcome = await workflow.start(request: transcript, context: context, telemetry: telemetry, onProgress: showWorkflowProgress)
            guard !Task.isCancelled else { return }
            await handleWorkflowOutcome(outcome, transcript: transcript, telemetry: telemetry)
            workflowTask = nil
        }
    }

    private func showWorkflowProgress(step: Int, tool: ToolDefinition, confidence: Double) {
        let local = tool.id.hasPrefix("text.")
        panel.update(.init(
            phase: .executing,
            transcript: currentTranscript,
            detail: local ? "Step \(step): local Gemma is transforming text…" : "Step \(step): running the Jev-selected tool…",
            expanded: true,
            tool: tool.title,
            confidence: confidence
        ))
    }

    private func handleWorkflowOutcome(_ outcome: WorkflowOutcome, transcript: String, telemetry: RequestTelemetry) async {
        if case .confirmation = outcome { await telemetry.pauseForConfirmation() }
        let metrics = await telemetry.snapshot()
        guard requestTelemetry === telemetry else { return }
        switch outcome {
        case .completed(let result, let records):
            pending = nil
            let tool = records.last?.title ?? "Complete"
            let detail = result.output.isEmpty ? result.summary : String(result.output.prefix(220))
            panel.update(.init(phase: .success, transcript: transcript, detail: detail, expanded: true, tool: tool, confidence: 1, requestMetrics: metrics))
            let spoken = records.last?.toolID.hasPrefix("text.") == true && !result.output.isEmpty
                ? result.output : result.summary
            spokenResponse.speak(spoken)
            scheduleCollapse(after: 4.0)
        case .confirmation(let pending):
            self.pending = pending
            let decision = pending.decision
            let preview = pending.preview.isEmpty ? "Confirm: \(decision.tool.title)" : pending.preview
            panel.update(.init(phase: .confirm, transcript: transcript, detail: preview, expanded: true, tool: decision.tool.title, confidence: decision.confidence, needsConfirmation: true, requestMetrics: metrics))
            let announcement = decision.tool.id.hasPrefix("messages.send")
                ? "Message ready. Review the recipient and text, then confirm in the notch."
                : "Review and confirm \(decision.tool.title.lowercased()) in the notch."
            spokenResponse.speak(announcement)
        case .failed(let message, let records):
            pending = nil
            let tool = records.last?.title ?? "Workflow"
            panel.update(.init(phase: .error, transcript: transcript, detail: message, expanded: true, tool: tool, requestMetrics: metrics))
            spokenResponse.speak(message)
            scheduleCollapse(after: 5.0)
        }
    }

    private func showFailure(_ message: String) {
        isListening = false; speech.cancel(); pending = nil
        spokenResponse.speak(message)
        panel.update(.init(phase: .error, transcript: currentTranscript, detail: message, expanded: true))
        if let telemetry = requestTelemetry {
            Task {
                let metrics = await telemetry.snapshot()
                guard self.requestTelemetry === telemetry else { return }
                self.panel.update(.init(phase: .error, transcript: self.currentTranscript, detail: message, expanded: true, requestMetrics: metrics))
            }
        }
        scheduleCollapse(after: 4.5)
    }

    private func scheduleCollapse(after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.pending == nil, !self.isListening else { return }
            self.panel.update(.init(phase: .idle, detail: "Hold Command to speak", expanded: false))
        }
    }

    func notchDidConfirm() {
        guard let pending else { return }
        self.pending = nil
        let telemetry = requestTelemetry ?? RequestTelemetry()
        requestTelemetry = telemetry
        workflowTask?.cancel()
        workflowTask = Task {
            await telemetry.resumeAfterConfirmation()
            let outcome = await workflow.resume(pending, telemetry: telemetry, onProgress: showWorkflowProgress)
            guard !Task.isCancelled else { return }
            await handleWorkflowOutcome(outcome, transcript: pending.state.request, telemetry: telemetry)
            workflowTask = nil
        }
    }

    func notchDidCancel() {
        pending = nil
        spokenResponse.stop()
        requestTelemetry = nil
        panel.update(.init(phase: .idle, detail: "Cancelled", expanded: false))
    }

    func notchDidDismiss() {
        cancelVoiceSession()
    }

    private func cancelVoiceSession() {
        holdTimer?.invalidate(); holdTimer = nil
        workflowTask?.cancel(); workflowTask = nil
        speech.cancel(); isListening = false; pending = nil; currentTranscript = ""; requestTelemetry = nil
        spokenResponse.stop()
        panel.update(.init(phase: .idle, detail: "Hold Command to speak", expanded: false))
    }

    func notchDidQuit() {
        speech.cancel()
        spokenResponse.stop()
        NSApp.terminate(nil)
    }

    private func installMenuBarItem() {
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "waveform.badge.mic", accessibilityDescription: "Jev Notch")
        let menu = NSMenu()
        menu.addItem(withTitle: "Set TypeSafe API Key…", action: #selector(promptForAPIKey), keyEquivalent: "")
        menu.addItem(withTitle: "Set Spotify Client ID…", action: #selector(promptForSpotifyClientID), keyEquivalent: "")
        menu.addItem(withTitle: "Connect Spotify…", action: #selector(connectSpotify), keyEquivalent: "")
        menu.addItem(withTitle: "Request Accessibility Permission", action: #selector(requestAccessibility), keyEquivalent: "")
        menu.addItem(.separator())
        let speechItem = NSMenuItem(title: "Speak Responses", action: #selector(toggleSpokenResponses(_:)), keyEquivalent: "")
        speechItem.state = spokenResponse.isEnabled ? .on : .off
        speechItem.target = self
        menu.addItem(speechItem)
        let voices = NSMenu(title: "ONNX Voice")
        for voice in spokenResponse.availableVoices {
            let option = NSMenuItem(title: SpokenResponse.displayName(for: voice), action: #selector(selectSpokenVoice(_:)), keyEquivalent: "")
            option.representedObject = voice.path
            option.state = spokenResponse.selectedVoiceURL?.path == voice.path ? .on : .off
            option.target = self
            voices.addItem(option)
        }
        if voices.items.isEmpty {
            let missing = NSMenuItem(title: "No Piper ONNX voices found", action: nil, keyEquivalent: "")
            missing.isEnabled = false
            voices.addItem(missing)
        }
        voices.addItem(.separator())
        let chooseVoice = NSMenuItem(title: "Choose ONNX Voice…", action: #selector(chooseONNXVoice), keyEquivalent: "")
        chooseVoice.target = self
        voices.addItem(chooseVoice)
        let voiceItem = NSMenuItem(title: "ONNX Voice", action: nil, keyEquivalent: "")
        voiceItem.submenu = voices
        menu.addItem(voiceItem)
        menu.addItem(withTitle: "Test Voice", action: #selector(testSpokenVoice), keyEquivalent: "")
        menu.addItem(withTitle: "Stop Speaking", action: #selector(stopSpeaking), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Jev Notch", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }
        item.menu = menu; statusItem = item
    }

    @objc private func requestAccessibility() { _ = SystemContext.accessibilityTrusted(prompt: true) }

    @objc private func toggleSpokenResponses(_ sender: NSMenuItem) {
        spokenResponse.isEnabled.toggle()
        sender.state = spokenResponse.isEnabled ? .on : .off
    }

    @objc private func selectSpokenVoice(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String,
              spokenResponse.selectVoice(URL(fileURLWithPath: path)) else { return }
        sender.menu?.items.forEach { $0.state = $0 === sender ? .on : .off }
        spokenResponse.speak("Voice ready.", force: true)
    }

    @objc private func chooseONNXVoice() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "onnx") ?? .data]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard spokenResponse.selectVoice(url) else {
            let alert = NSAlert()
            alert.messageText = "This ONNX voice needs a matching .onnx.json file beside it."
            alert.runModal()
            return
        }
        if let menu = statusItem?.menu?.items.first(where: { $0.title == "ONNX Voice" })?.submenu {
            if !menu.items.contains(where: { $0.representedObject as? String == url.path }) {
                let option = NSMenuItem(title: SpokenResponse.displayName(for: url), action: #selector(selectSpokenVoice(_:)), keyEquivalent: "")
                option.representedObject = url.path
                option.target = self
                menu.insertItem(option, at: 0)
            }
            for item in menu.items where item.representedObject is String {
                item.state = (item.representedObject as? String == url.path) ? .on : .off
            }
        }
        spokenResponse.speak("Voice ready.", force: true)
    }

    @objc private func testSpokenVoice() {
        spokenResponse.speak("Voice ready. What would you like me to do?", force: true) { error in
            let alert = NSAlert()
            alert.messageText = "ONNX voice unavailable"
            alert.informativeText = error
            alert.runModal()
        }
    }

    @objc private func stopSpeaking() { spokenResponse.stop() }

    @objc private func promptForAPIKey() {
        let alert = NSAlert(); alert.messageText = "TypeSafe API Key"; alert.informativeText = "Stored only in your macOS Keychain."
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 360, height: 24)); field.placeholderString = "apikey_…"; alert.accessoryView = field
        alert.addButton(withTitle: "Save"); alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn, !field.stringValue.isEmpty else { return }
        do { try KeychainStore.saveAPIKey(field.stringValue) }
        catch { showFailure(error.localizedDescription) }
    }

    @objc private func promptForSpotifyClientID() {
        let alert = NSAlert()
        alert.messageText = "Spotify Client ID"
        alert.informativeText = "Register \(SpotifyOAuth.redirectURI) as the redirect URI in your Spotify developer app, then paste its Client ID."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 400, height: 24))
        field.placeholderString = "Spotify Client ID"
        field.stringValue = SpotifyOAuth.clientID ?? ""
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        UserDefaults.standard.set(value, forKey: SpotifyOAuth.clientIDKey)
    }

    @objc private func connectSpotify() {
        Task {
            do {
                try await SpotifyOAuth.shared.connect()
                panel.update(.init(phase: .success, detail: "Spotify connected. Say a song title and artist.", expanded: true))
                scheduleCollapse(after: 4)
            } catch { showFailure(error.localizedDescription) }
        }
    }
}
