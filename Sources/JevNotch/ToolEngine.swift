import AppKit
import ApplicationServices
import Foundation

final class ToolEngine {
    private let ollama = OllamaTextClient()

    func prewarmTextModel() async { await ollama.prewarm() }

    let tools: [ToolDefinition] = [
        .init(id: "workflow.finish", title: "Finish workflow", description: "Stop only when every part of the request has been completed by prior successful steps.", risk: .read),
        .init(id: "system.state", title: "Inspect current context", description: "Report the frontmost app, focused window, and focused control.", risk: .read),
        .init(id: "apps.list", title: "List running applications", description: "Report apps currently running on the Mac.", risk: .read),
        .init(id: "app.open", title: "Open application", description: "Launch an application named in the request.", risk: .reversible),
        .init(id: "app.activate", title: "Switch application", description: "Bring a running application to the front.", risk: .reversible),
        .init(id: "app.hide", title: "Hide application", description: "Hide an application without quitting it.", risk: .reversible),
        .init(id: "app.quit", title: "Quit application", description: "Terminate an application; unsaved work may be lost.", risk: .consequential),
        .init(id: "browser.open_url", title: "Open web address", description: "Open a spoken URL or website in the default browser.", risk: .reversible),
        .init(id: "file.open", title: "Open file", description: "Open a local path mentioned in the request.", risk: .reversible),
        .init(id: "keyboard.type", title: "Type text", description: "Insert dictated text into the focused field without pressing Enter or submitting.", risk: .reversible),
        .init(id: "keyboard.copy", title: "Copy", description: "Send Command-C to the frontmost application.", risk: .reversible),
        .init(id: "keyboard.paste", title: "Paste", description: "Send Command-V to the frontmost application without submitting.", risk: .reversible),
        .init(id: "keyboard.cut", title: "Cut", description: "Send Command-X to the frontmost application.", risk: .consequential),
        .init(id: "keyboard.undo", title: "Undo", description: "Send Command-Z to the frontmost application.", risk: .reversible),
        .init(id: "keyboard.redo", title: "Redo", description: "Send Shift-Command-Z to the frontmost application.", risk: .reversible),
        .init(id: "keyboard.select_all", title: "Select all", description: "Send Command-A to the frontmost application.", risk: .reversible),
        .init(id: "clipboard.read", title: "Read clipboard", description: "Describe the current text clipboard contents.", risk: .read),
        .init(id: "clipboard.write", title: "Set clipboard", description: "Copy dictated content to the clipboard.", risk: .reversible),
        .init(id: "clipboard.clear", title: "Clear clipboard", description: "Erase the current clipboard contents.", risk: .consequential),
        .init(id: "window.close", title: "Close window", description: "Close the focused window; unsaved work may be affected.", risk: .consequential),
        .init(id: "window.minimize", title: "Minimize window", description: "Minimize the focused window.", risk: .reversible),
        .init(id: "window.fullscreen", title: "Toggle full screen", description: "Toggle the focused window full-screen state.", risk: .reversible),
        .init(id: "ui.click", title: "Click named control", description: "Press an exact, unique visible button or link in the current app or browser using Accessibility.", risk: .reversible),
        .init(id: "ui.inspect", title: "Inspect visible controls", description: "Read a compact list of controls in the focused window before another computer-use step.", risk: .read),
        .init(id: "ui.scroll_up", title: "Scroll up", description: "Scroll the current interface upward.", risk: .reversible),
        .init(id: "ui.scroll_down", title: "Scroll down", description: "Scroll the current interface downward.", risk: .reversible),
        .init(id: "system.volume_set", title: "Set volume", description: "Set output volume to a spoken percentage.", risk: .reversible),
        .init(id: "system.mute", title: "Mute", description: "Mute system audio.", risk: .reversible),
        .init(id: "system.unmute", title: "Unmute", description: "Unmute system audio.", risk: .reversible),
        .init(id: "media.play_pause", title: "Play or pause media", description: "Toggle playback in the Music app.", risk: .reversible),
        .init(id: "media.next", title: "Next media item", description: "Skip to the next track in the Music app.", risk: .reversible),
        .init(id: "media.previous", title: "Previous media item", description: "Go to the previous track in the Music app.", risk: .reversible),
        .init(id: "spotify.play", title: "Play a Spotify song", description: "Find a named song or artist and play it in Spotify; verify the actual current track.", risk: .reversible),
        .init(id: "spotify.resume", title: "Resume Spotify", description: "Resume Spotify playback.", risk: .reversible),
        .init(id: "spotify.pause", title: "Pause Spotify", description: "Pause Spotify playback.", risk: .reversible),
        .init(id: "spotify.next", title: "Skip Spotify song", description: "Skip to the next Spotify track.", risk: .reversible),
        .init(id: "spotify.previous", title: "Previous Spotify song", description: "Return to the previous Spotify track.", risk: .reversible),
        .init(id: "spotify.now_playing", title: "Spotify now playing", description: "Read and verify Spotify's current track and playback state.", risk: .read),
        .init(id: "messages.draft", title: "Draft a text message without sending", description: "Choose only when the user explicitly says draft, compose, or write a message without asking to send or text the recipient.", risk: .read),
        .init(id: "messages.send", title: "Send or text a person", description: "Choose for 'text Alex saying ...', 'message Alex ...', or 'send a message to Alex ...'. Resolve exact recipient, preview, confirm, then send in Messages.", risk: .consequential),
        .init(id: "messages.send_sms", title: "Send an SMS", description: "Choose only when the user explicitly requests SMS. Resolve exact phone number, preview, confirm, then send through the paired iPhone SMS service.", risk: .consequential),
        .init(id: "shortcut.run", title: "Run Shortcut", description: "Run an Apple Shortcut by spoken name.", risk: .consequential),
        .init(id: "shell.run", title: "Run shell command", description: "Run an explicitly dictated shell command. Always requires confirmation.", risk: .consequential),
        .init(id: "text.generate", title: "Generate text locally", description: "Use local Gemma only to compose prose after Jev selects this step. It cannot call tools.", risk: .read),
        .init(id: "text.rewrite", title: "Rewrite text locally", description: "Use local Gemma to rewrite the latest observed or generated text.", risk: .read),
        .init(id: "text.summarize", title: "Summarize text locally", description: "Use local Gemma to summarize the latest tool output, selected text, or clipboard text.", risk: .read),
        .init(id: "text.answer", title: "Answer from current text", description: "Answer a question using only readable text from the current browser page, selected text, clipboard, or a prior tool result. Never invent an answer not in that source.", risk: .read),
        .init(id: "text.extract_actions", title: "Extract action items locally", description: "Use local Gemma to extract supported action items from the latest text.", risk: .read),
        .init(id: "text.draft_email", title: "Draft email text locally", description: "Use local Gemma to compose an email body only; a separate Jev-selected email tool is required to draft or send it.", risk: .read),
        .init(id: "file.search", title: "Search local files", description: "Search Spotlight for files matching words in the request.", risk: .read),
        .init(id: "file.read_text", title: "Read local text file", description: "Read a text file returned by an earlier step or named in the request.", risk: .read),
        .init(id: "browser.current_url", title: "Read browser URL", description: "Read the URL of the active Safari or Chrome tab.", risk: .read),
        .init(id: "browser.page_text", title: "Read browser page", description: "Read visible text from the active Dia, Safari, or Chrome page for a later text operation.", risk: .read),
        .init(id: "browser.back", title: "Browser back", description: "Navigate the active browser tab backward.", risk: .reversible),
        .init(id: "browser.forward", title: "Browser forward", description: "Navigate the active browser tab forward.", risk: .reversible),
        .init(id: "browser.reload", title: "Reload browser", description: "Reload the active browser tab.", risk: .reversible),
        .init(id: "browser.new_tab", title: "New browser tab", description: "Open a new tab, optionally using a URL stated by the user.", risk: .reversible),
        .init(id: "browser.search", title: "Search the web", description: "Search the web for spoken terms in a new tab of the active browser.", risk: .reversible),
        .init(id: "browser.find_text", title: "Find text on this page", description: "Open the browser's Find bar and search for spoken text on the current page.", risk: .reversible),
        .init(id: "browser.click", title: "Click browser control", description: "Press an exact, unique named button or link in the active browser page using Accessibility.", risk: .reversible),
        .init(id: "browser.next_tab", title: "Next browser tab", description: "Switch to the next browser tab.", risk: .reversible),
        .init(id: "browser.previous_tab", title: "Previous browser tab", description: "Switch to the previous browser tab.", risk: .reversible),
        .init(id: "browser.close_tab", title: "Close browser tab", description: "Close the active browser tab; unsaved form content may be lost.", risk: .consequential),
        .init(id: "calendar.today", title: "Read today's calendar", description: "List today's Calendar events.", risk: .read),
        .init(id: "calendar.create", title: "Create calendar event", description: "Create an event when the request includes a recognizable date and time.", risk: .consequential),
        .init(id: "reminder.list", title: "List reminders", description: "List incomplete reminders.", risk: .read),
        .init(id: "reminder.create", title: "Create reminder", description: "Create a reminder, optionally with a recognized due date.", risk: .consequential),
        .init(id: "notes.search", title: "Search notes", description: "Search Apple Notes titles and bodies.", risk: .read),
        .init(id: "notes.create", title: "Create note", description: "Create an Apple Note from the latest generated text or request.", risk: .consequential),
        .init(id: "email.search", title: "Search email", description: "Search recent Mail messages by sender, subject, or terms.", risk: .read),
        .init(id: "email.draft", title: "Create email draft", description: "Create a Mail draft using an explicit email address and the latest generated text.", risk: .consequential),
        .init(id: "contact.search", title: "Find contact", description: "Find matching contacts and their available email addresses.", risk: .read),
        .init(id: "window.tile_left", title: "Tile window left", description: "Move and resize the focused window to the left half of the visible screen.", risk: .reversible),
        .init(id: "window.tile_right", title: "Tile window right", description: "Move and resize the focused window to the right half of the visible screen.", risk: .reversible),
    ]

    func execute(_ tool: ToolDefinition, transcript: String, workflow: WorkflowState? = nil) async -> ToolResult {
        switch tool.id {
        case "workflow.finish":
            let last = workflow?.records.last
            return ok(last?.summary ?? "Request completed.", output: last?.output ?? "")
        case "system.state":
            let state = SystemContext.snapshot()
            let value = "Frontmost: \(state["frontmost_app"] ?? "unknown"); focus: \(state["focused_element"] ?? "unknown")."
            return ok(value, output: value)
        case "apps.list":
            let names = NSWorkspace.shared.runningApplications.compactMap(\.localizedName).uniqued().sorted()
            let value = names.prefix(12).joined(separator: ", ")
            return ok(value, output: value)
        case "app.open": return openApplication(from: transcript, activateOnly: false)
        case "app.activate": return openApplication(from: transcript, activateOnly: true)
        case "app.hide", "app.quit": return controlApplication(from: transcript, quit: tool.id == "app.quit")
        case "browser.open_url": return openURL(from: transcript)
        case "file.open": return openFile(from: transcript)
        case "keyboard.type": return typeText(extractPayload(transcript, markers: ["type", "write", "insert"]))
        case "keyboard.copy": return hotkey(keyCode: 8, flags: .maskCommand, summary: "Copied selection.")
        case "keyboard.paste": return hotkey(keyCode: 9, flags: .maskCommand, summary: "Pasted clipboard.")
        case "keyboard.cut": return hotkey(keyCode: 7, flags: .maskCommand, summary: "Cut selection.")
        case "keyboard.undo": return hotkey(keyCode: 6, flags: .maskCommand, summary: "Undid the last action.")
        case "keyboard.redo": return hotkey(keyCode: 6, flags: [.maskCommand, .maskShift], summary: "Redid the last action.")
        case "keyboard.select_all": return hotkey(keyCode: 0, flags: .maskCommand, summary: "Selected all.")
        case "clipboard.read":
            let text = NSPasteboard.general.string(forType: .string) ?? "Clipboard has no text."
            return ok(text.count > 180 ? String(text.prefix(180)) + "…" : text, output: text)
        case "clipboard.write":
            let value = extractPayload(transcript, markers: ["copy", "clipboard", "set clipboard to"])
            guard !value.isEmpty else { return fail("I couldn't identify what to copy.") }
            NSPasteboard.general.clearContents(); NSPasteboard.general.setString(value, forType: .string)
            return ok("Copied “\(value.prefix(80))” to the clipboard.")
        case "clipboard.clear": NSPasteboard.general.clearContents(); return ok("Clipboard cleared.")
        case "window.close": return windowAction(kAXCloseButtonAttribute, action: kAXPressAction, summary: "Closed the focused window.")
        case "window.minimize": return setWindowAttribute(kAXMinimizedAttribute, value: true, summary: "Minimized the focused window.")
        case "window.fullscreen": return toggleFullscreen()
        case "ui.click": return clickNamed(extractPayload(transcript, markers: ["click", "press", "select"]))
        case "ui.inspect":
            let value = SystemContext.compactUITree()
            return value.isEmpty ? fail("No accessible controls were found in the focused window.") : ok("Inspected the focused window.", output: value)
        case "ui.scroll_up": return scroll(lines: 6)
        case "ui.scroll_down": return scroll(lines: -6)
        case "system.volume_set": return setVolume(from: transcript)
        case "system.mute": return runAppleScript("set volume with output muted", summary: "Muted system audio.")
        case "system.unmute": return runAppleScript("set volume without output muted", summary: "Unmuted system audio.")
        case "media.play_pause": return runAppleScript("tell application \"Music\" to playpause", summary: "Toggled playback.")
        case "media.next": return runAppleScript("tell application \"Music\" to next track", summary: "Skipped to the next track.")
        case "media.previous": return runAppleScript("tell application \"Music\" to previous track", summary: "Went to the previous track.")
        case "spotify.play", "spotify.resume", "spotify.pause", "spotify.next", "spotify.previous", "spotify.now_playing":
            return await SpotifyAdapter.execute(tool.id, transcript: transcript)
        case "messages.draft": return await MessagesAdapter.prepare(transcript, workflow: workflow)
        case "messages.send", "messages.send_sms":
            return await Task.detached(priority: .userInitiated) {
                MessagesAdapter.send(workflow: workflow, sms: tool.id == "messages.send_sms")
            }.value
        case "shortcut.run": return runProcess("/usr/bin/shortcuts", ["run", extractPayload(transcript, markers: ["run shortcut", "shortcut"])], summary: "Shortcut finished.")
        case "shell.run":
            let command = extractPayload(transcript, markers: ["run command", "shell", "terminal"])
            guard !command.isEmpty else { return fail("No shell command was found.") }
            return runProcess("/bin/zsh", ["-lc", command], summary: "Command finished.")
        case "text.generate", "text.rewrite", "text.summarize", "text.answer", "text.extract_actions", "text.draft_email":
            return await runTextOperation(tool.id, transcript: transcript, workflow: workflow)
        case "file.search": return searchFiles(from: transcript)
        case "file.read_text": return readTextFile(from: transcript, workflow: workflow)
        case "browser.current_url", "browser.page_text", "browser.back", "browser.forward", "browser.reload", "browser.new_tab", "browser.search", "browser.find_text", "browser.click", "browser.next_tab", "browser.previous_tab", "browser.close_tab":
            return browserAction(tool.id, transcript: transcript)
        case "calendar.today", "calendar.create", "reminder.list", "reminder.create", "notes.search", "notes.create", "email.search", "email.draft", "contact.search", "window.tile_left", "window.tile_right":
            return await HighROIToolAdapters.execute(tool.id, transcript: transcript, workflow: workflow)
        default: return fail("That tool is not available in this build.")
        }
    }

    private func openApplication(from text: String, activateOnly: Bool) -> ToolResult {
        let requested = extractPayload(text, markers: activateOnly ? ["switch to", "activate", "focus"] : ["open", "launch", "start"])
        guard !requested.isEmpty else { return fail("I couldn't identify the application.") }
        if let running = bestApplication(named: requested, in: NSWorkspace.shared.runningApplications) {
            running.activate(options: [.activateAllWindows])
            return ok("Switched to \(running.localizedName ?? requested).")
        }
        guard !activateOnly else { return fail("\(requested) is not running.") }
        guard let url = applicationURL(named: requested) else { return fail("I couldn't find \(requested).") }
        guard NSWorkspace.shared.open(url) else { return fail("Could not open \(requested).") }
        return ok("Opened \(requested).")
    }

    private func applicationURL(named requested: String) -> URL? {
        let appName = requested.lowercased().hasSuffix(".app") ? requested : "\(requested).app"
        let roots = ["/Applications", "/System/Applications", "/System/Applications/Utilities", ("~/Applications" as NSString).expandingTildeInPath]
        for root in roots {
            let candidate = URL(fileURLWithPath: root).appendingPathComponent(appName)
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        let queryName = requested.replacingOccurrences(of: "\"", with: "")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
        process.arguments = ["kMDItemContentType == 'com.apple.application-bundle' && kMDItemDisplayName ==[c] '\(queryName)'"]
        let pipe = Pipe(); process.standardOutput = pipe; process.standardError = Pipe()
        guard (try? process.run()) != nil else { return nil }
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let first = String(data: data, encoding: .utf8)?.split(separator: "\n").first else { return nil }
        return URL(fileURLWithPath: String(first))
    }

    private func controlApplication(from text: String, quit: Bool) -> ToolResult {
        let name = extractPayload(text, markers: quit ? ["quit", "close", "terminate"] : ["hide"])
        guard let app = bestApplication(named: name, in: NSWorkspace.shared.runningApplications) else { return fail("I couldn't find that running app.") }
        if quit { app.terminate() } else { app.hide() }
        return ok("\(quit ? "Quit" : "Hid") \(app.localizedName ?? name).")
    }

    private func bestApplication(named name: String, in apps: [NSRunningApplication]) -> NSRunningApplication? {
        let needle = normalize(name)
        return apps.first { normalize($0.localizedName ?? "") == needle }
            ?? apps.first { normalize($0.localizedName ?? "").contains(needle) || needle.contains(normalize($0.localizedName ?? "")) }
    }

    private func openURL(from text: String) -> ToolResult {
        let raw = extractPayload(text, markers: ["open website", "open url", "go to", "visit", "open"])
            .replacingOccurrences(of: " dot ", with: ".")
            .replacingOccurrences(of: " slash ", with: "/")
            .replacingOccurrences(of: " ", with: "")
        let candidate = raw.contains("://") ? raw : "https://\(raw)"
        guard let url = URL(string: candidate), url.host != nil else { return fail("I couldn't identify a valid web address.") }
        NSWorkspace.shared.open(url)
        return ok("Opened \(url.host ?? candidate).")
    }

    private func openFile(from text: String) -> ToolResult {
        let path = (extractPayload(text, markers: ["open file", "open"] ) as NSString).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: path) else { return fail("That file does not exist: \(path)") }
        NSWorkspace.shared.open(URL(fileURLWithPath: path)); return ok("Opened \((path as NSString).lastPathComponent).")
    }

    private func typeText(_ text: String) -> ToolResult {
        guard !text.isEmpty else { return fail("I couldn't identify the text to type.") }
        guard SystemContext.accessibilityTrusted(prompt: true) else { return fail("Accessibility permission is required to type into other apps.") }
        let source = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
        var units = Array(text.utf16)
        down?.keyboardSetUnicodeString(stringLength: units.count, unicodeString: &units)
        down?.post(tap: .cghidEventTap)
        CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)?.post(tap: .cghidEventTap)
        return ok("Typed the dictated text.")
    }

    private func hotkey(keyCode: CGKeyCode, flags: CGEventFlags, summary: String) -> ToolResult {
        guard SystemContext.accessibilityTrusted(prompt: true) else { return fail("Accessibility permission is required for keyboard commands.") }
        let source = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        down?.flags = flags; down?.post(tap: .cghidEventTap)
        let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        up?.flags = flags; up?.post(tap: .cghidEventTap)
        return ok(summary)
    }

    private func scroll(lines: Int32) -> ToolResult {
        guard SystemContext.accessibilityTrusted(prompt: true) else { return fail("Accessibility permission is required to scroll other apps.") }
        let event = CGEvent(scrollWheelEvent2Source: CGEventSource(stateID: .hidSystemState), units: .line, wheelCount: 1, wheel1: lines, wheel2: 0, wheel3: 0)
        event?.post(tap: .cghidEventTap)
        return ok(lines > 0 ? "Scrolled up." : "Scrolled down.")
    }

    private func setVolume(from text: String) -> ToolResult {
        let match = text.range(of: #"\b([0-9]{1,3})\b"#, options: .regularExpression)
        let value = match.flatMap { Int(text[$0]) }.map { min(100, max(0, $0)) }
        guard let value else { return fail("Say a volume percentage from 0 to 100.") }
        return runAppleScript("set volume output volume \(value)", summary: "Set volume to \(value) percent.")
    }

    private func windowAction(_ attribute: String, action: String, summary: String) -> ToolResult {
        guard let window = SystemContext.frontWindow() else { return fail("No focused window was found.") }
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, attribute as CFString, &raw) == .success, let raw else { return fail("That window does not expose this control.") }
        let element = raw as! AXUIElement
        guard AXUIElementPerformAction(element, action as CFString) == .success else { return fail("The window rejected the action.") }
        return ok(summary)
    }

    private func setWindowAttribute(_ attribute: String, value: Bool, summary: String) -> ToolResult {
        guard let window = SystemContext.frontWindow() else { return fail("No focused window was found.") }
        let result = AXUIElementSetAttributeValue(window, attribute as CFString, value as CFBoolean)
        return result == .success ? ok(summary) : fail("The window rejected the action.")
    }

    private func toggleFullscreen() -> ToolResult {
        guard let window = SystemContext.frontWindow() else { return fail("No focused window was found.") }
        var raw: CFTypeRef?
        let attribute = "AXFullScreen" as CFString
        AXUIElementCopyAttributeValue(window, attribute, &raw)
        let current = (raw as? Bool) ?? false
        let result = AXUIElementSetAttributeValue(window, attribute, (!current) as CFBoolean)
        return result == .success ? ok(current ? "Exited full screen." : "Entered full screen.") : fail("The window does not support full screen.")
    }

    private func clickNamed(_ name: String) -> ToolResult {
        let cleaned = name
            .replacingOccurrences(of: #"(?i)^the\s+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\s+(button|link|control)(?:\s+(on|in)\s+(this\s+)?(page|browser|app))?$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return fail("I couldn't identify which control to click.") }
        guard let window = SystemContext.frontWindow(), let element = SystemContext.findElement(named: cleaned, in: window) else { return fail("I couldn't find one unique pressable control named \(cleaned).") }
        guard AXUIElementPerformAction(element, kAXPressAction as CFString) == .success else { return fail("That control could not be pressed.") }
        return ok("Pressed \(cleaned).")
    }

    private func runAppleScript(_ source: String, summary: String) -> ToolResult {
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error { return fail(error[NSAppleScript.errorMessage] as? String ?? "AppleScript failed.") }
        return ok(summary)
    }

    private func runProcess(_ executable: String, _ arguments: [String], summary: String) -> ToolResult {
        guard arguments.allSatisfy({ !$0.isEmpty }) else { return fail("The command is missing a required name or argument.") }
        let process = Process(); process.executableURL = URL(fileURLWithPath: executable); process.arguments = arguments
        let pipe = Pipe(); process.standardOutput = pipe; process.standardError = pipe
        do { try process.run(); process.waitUntilExit() } catch { return fail(error.localizedDescription) }
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard process.terminationStatus == 0 else { return fail(output.isEmpty ? "Command failed with status \(process.terminationStatus)." : String(output.prefix(180))) }
        return ok(output.isEmpty ? summary : String(output.prefix(180)), output: output)
    }

    private func runTextOperation(_ toolID: String, transcript: String, workflow: WorkflowState?) async -> ToolResult {
        let operation: TextOperation = switch toolID {
        case "text.rewrite": .rewrite
        case "text.summarize": .summarize
        case "text.answer": .answer
        case "text.extract_actions": .extractActions
        case "text.draft_email": .draftEmail
        default: .generate
        }
        let hint = TextSourceHint.explicit(in: transcript)
        let source: String?
        switch hint {
        case .page:
            let page = browserAction("browser.page_text", transcript: transcript)
            source = page.success ? page.output : nil
        case .selection:
            source = SystemContext.selectedText()
        case .clipboard:
            source = NSPasteboard.general.string(forType: .string)
        case nil:
            let prior = workflow?.records.last(where: { !$0.output.isEmpty })?.output
            source = prior ?? SystemContext.selectedText()
                ?? ((operation == .generate || operation == .draftEmail) ? transcript : nil)
        }
        guard let source, !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return fail(hint?.unavailableMessage ?? "Select text or say ‘this page’ or ‘clipboard’ so I know what to read.")
        }
        guard await ollama.ensureAvailable() else {
            return fail("Ollama could not start or gemma3:4b is not installed.")
        }
        do {
            let value = try await ollama.generate(operation: operation, request: transcript, source: source)
            return ok("Gemma completed the \(operation.rawValue) step.", output: value, artifacts: ["generated_text": value])
        } catch {
            return fail("Local text generation failed: \(error.localizedDescription)")
        }
    }

    private func searchFiles(from transcript: String) -> ToolResult {
        let query = extractPayload(transcript, markers: ["search files for", "find file", "find", "search"])
        guard !query.isEmpty else { return fail("Say what file to search for.") }
        let result = runProcess("/usr/bin/mdfind", ["-interpret", query], summary: "No matching files were found.")
        guard result.success, !result.output.isEmpty else { return result }
        let paths = result.output.split(separator: "\n").prefix(20).map(String.init)
        return ok("Found \(paths.count) matching files. First: \((paths.first! as NSString).lastPathComponent)", output: paths.joined(separator: "\n"), artifacts: ["file_path": paths.first!])
    }

    private func readTextFile(from transcript: String, workflow: WorkflowState?) -> ToolResult {
        let candidate = workflow?.artifacts["file_path"]
            ?? extractPayload(transcript, markers: ["read file", "read", "open file"])
        let path = (candidate as NSString?)?.expandingTildeInPath ?? ""
        guard !path.isEmpty, FileManager.default.fileExists(atPath: path) else { return fail("No readable file path is available.") }
        guard let data = FileManager.default.contents(atPath: path), data.count <= 4_000_000 else { return fail("The file is unavailable or too large to read safely.") }
        let value = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .utf16)
        guard let value else { return fail("That file is not plain text.") }
        return ok("Read \((path as NSString).lastPathComponent).", output: String(value.prefix(40_000)), artifacts: ["file_path": path])
    }

    private func browserAction(_ toolID: String, transcript: String) -> ToolResult {
        let app = NSWorkspace.shared.frontmostApplication?.localizedName ?? ""
        let chrome = app.localizedCaseInsensitiveContains("Chrome")
        let safari = app.localizedCaseInsensitiveContains("Safari")
        let dia = app.localizedCaseInsensitiveContains("Dia")
        guard chrome || safari || dia else { return fail("Bring Dia, Safari, or Chrome to the front first.") }

        switch toolID {
        case "browser.click": return clickNamed(extractPayload(transcript, markers: ["click", "press", "select"]))
        case "browser.find_text":
            let phrase = extractPayload(transcript, markers: ["find on page", "find in page", "find text", "find"])
            guard !phrase.isEmpty else { return fail("Say what text to find.") }
            let opened = hotkey(keyCode: 3, flags: .maskCommand, summary: "Opened browser Find.")
            guard opened.success else { return opened }
            return typeText(phrase)
        case "browser.next_tab": return hotkey(keyCode: 48, flags: .maskControl, summary: "Switched to the next tab.")
        case "browser.previous_tab": return hotkey(keyCode: 48, flags: [.maskControl, .maskShift], summary: "Switched to the previous tab.")
        case "browser.close_tab": return hotkey(keyCode: 13, flags: .maskCommand, summary: "Closed the current tab.")
        case "browser.search":
            let query = extractPayload(transcript, markers: ["search the web for", "search google for", "search for", "search"])
            guard !query.isEmpty else { return fail("Say what to search for.") }
            var components = URLComponents(string: "https://www.google.com/search")!
            components.queryItems = [.init(name: "q", value: query)]
            return browserAction("browser.new_tab", transcript: "new tab \(components.url!.absoluteString)")
        default: break
        }

        if dia {
            switch toolID {
            case "browser.current_url":
                return runAppleScriptWithOutput("tell application \"Dia\" to get URL of active tab of front window", summary: "Read Dia's active URL.")
            case "browser.page_text":
                let text = SystemContext.visiblePageText()
                return text.isEmpty ? fail("Dia did not expose readable page text through Accessibility.") : ok("Read visible page text.", output: text)
            case "browser.back": return hotkey(keyCode: 33, flags: .maskCommand, summary: "Navigated back in Dia.")
            case "browser.forward": return hotkey(keyCode: 30, flags: .maskCommand, summary: "Navigated forward in Dia.")
            case "browser.reload": return hotkey(keyCode: 15, flags: .maskCommand, summary: "Reloaded Dia's active tab.")
            default:
                let raw = extractPayload(transcript, markers: ["new tab", "open tab"])
                    .replacingOccurrences(of: " dot ", with: ".")
                    .replacingOccurrences(of: " ", with: "")
                let url = raw.isEmpty ? "about:blank" : (raw.contains("://") ? raw : "https://\(raw)")
                guard url == "about:blank" || URL(string: url)?.host != nil else { return fail("That new-tab address is invalid.") }
                return runAppleScriptWithOutput("tell application \"Dia\" to tell front window to make new tab with properties {URL:\"\(appleScriptString(url))\"}", summary: "Opened a new Dia tab.")
            }
        }

        let script: String
        let summary: String
        switch toolID {
        case "browser.current_url":
            script = chrome
                ? "tell application \"Google Chrome\" to get URL of active tab of front window"
                : "tell application \"Safari\" to get URL of front document"
            summary = "Read the active tab URL."
        case "browser.page_text":
            script = chrome
                ? "tell application \"Google Chrome\" to execute active tab of front window javascript \"document.body.innerText\""
                : "tell application \"Safari\" to get text of front document"
            summary = "Read the active page text."
        case "browser.back":
            script = chrome
                ? "tell application \"Google Chrome\" to go back active tab of front window"
                : "tell application \"Safari\" to tell front document to do JavaScript \"history.back()\""
            summary = "Navigated back."
        case "browser.forward":
            script = chrome
                ? "tell application \"Google Chrome\" to go forward active tab of front window"
                : "tell application \"Safari\" to tell front document to do JavaScript \"history.forward()\""
            summary = "Navigated forward."
        case "browser.reload":
            script = chrome
                ? "tell application \"Google Chrome\" to reload active tab of front window"
                : "tell application \"Safari\" to tell front document to do JavaScript \"location.reload()\""
            summary = "Reloaded the active page."
        default:
            let raw = extractPayload(transcript, markers: ["new tab", "open tab"])
                .replacingOccurrences(of: " dot ", with: ".")
                .replacingOccurrences(of: " ", with: "")
            let url = raw.isEmpty ? "about:blank" : (raw.contains("://") ? raw : "https://\(raw)")
            let escaped = appleScriptString(url)
            script = chrome
                ? "tell application \"Google Chrome\" to tell front window to make new tab with properties {URL:\"\(escaped)\"}"
                : "tell application \"Safari\" to tell front window to set current tab to (make new tab with properties {URL:\"\(escaped)\"})"
            summary = "Opened a new browser tab."
        }
        let result = runAppleScriptWithOutput(script, summary: summary)
        if toolID == "browser.page_text" && !result.success {
            let text = SystemContext.visiblePageText()
            if !text.isEmpty { return ok("Read visible page text.", output: text) }
        }
        return result
    }

    private func runAppleScriptWithOutput(_ source: String, summary: String) -> ToolResult {
        var error: NSDictionary?
        let descriptor = NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error { return fail(error[NSAppleScript.errorMessage] as? String ?? "AppleScript failed.") }
        let value = descriptor?.stringValue ?? ""
        return ok(value.isEmpty ? summary : String(value.prefix(180)), output: value)
    }

    private func appleScriptString(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    func extractPayload(_ text: String, markers: [String]) -> String {
        let lower = text.lowercased()
        for marker in markers.sorted(by: { $0.count > $1.count }) {
            if let range = lower.range(of: marker) {
                return String(text[range.upperBound...]).trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
            }
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalize(_ value: String) -> String {
        value.lowercased().filter { $0.isLetter || $0.isNumber }
    }
    private func ok(_ message: String, output: String = "", artifacts: [String: String] = [:]) -> ToolResult {
        .init(success: true, summary: message, output: output, artifacts: artifacts)
    }
    private func fail(_ message: String) -> ToolResult { .init(success: false, summary: message) }
}

private extension Sequence where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
