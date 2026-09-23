import XCTest
@testable import JevNotch

final class ToolEngineTests: XCTestCase {
    func testPayloadExtractionPrefersLongestMarker() {
        let engine = ToolEngine()
        XCTAssertEqual(engine.extractPayload("Please open website example dot com", markers: ["open", "open website"]), "example dot com")
    }

    func testToolIdentifiersAreUnique() {
        let identifiers = ToolEngine().tools.map(\.id)
        XCTAssertEqual(Set(identifiers).count, identifiers.count)
    }

    func testConsequentialToolsIncludeShellAndQuit() {
        let risky = Set(ToolEngine().tools.filter { $0.risk == .consequential }.map(\.id))
        XCTAssertTrue(risky.contains("shell.run"))
        XCTAssertTrue(risky.contains("app.quit"))
    }

    func testExpandedCatalogHasHighROIDomains() {
        let identifiers = Set(ToolEngine().tools.map(\.id))
        XCTAssertGreaterThanOrEqual(identifiers.count, 50)
        for required in [
            "workflow.finish", "text.generate", "text.summarize",
            "calendar.create", "reminder.create", "browser.page_text",
            "email.draft", "notes.create", "contact.search", "file.search",
        ] {
            XCTAssertTrue(identifiers.contains(required), "Missing \(required)")
        }
    }

    func testLocalTextWorkerCannotBeRoutedAsConsequential() {
        let textTools = ToolEngine().tools.filter { $0.id.hasPrefix("text.") }
        XCTAssertFalse(textTools.isEmpty)
        XCTAssertTrue(textTools.allSatisfy { $0.risk == .read })
    }

    func testLiveJevHierarchicalRoutingWhenEnabled() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["JEV_LIVE_TEST"] == "1")
        let decision = try await JevClient().route(
            transcript: "List the applications that are running on this Mac",
            context: ["frontmost_app": "Finder", "focused_element": "window"],
            tools: ToolEngine().tools
        )
        XCTAssertEqual(decision.tool.id, "apps.list")
        XCTAssertGreaterThan(decision.confidence, 0.5)
    }

    func testMessageRecipientAndBodyParsing() {
        XCTAssertEqual(MessagesAdapter.parse("Text Alex saying I’m on my way"), .init(recipient: "Alex", body: "I’m on my way"))
        XCTAssertEqual(MessagesAdapter.parse("Send a message to Alex Chen saying Meet at six"), .init(recipient: "Alex Chen", body: "Meet at six"))
        XCTAssertEqual(MessagesAdapter.parse("Draft a text to +15551234567: Running late"), .init(recipient: "+15551234567", body: "Running late"))
        XCTAssertEqual(MessagesAdapter.parse("Send an SMS to +15551234567 saying Running late"), .init(recipient: "+15551234567", body: "Running late"))
        XCTAssertNil(MessagesAdapter.parse("send a message"))
    }

    @MainActor func testSpotifyQueryKeepsTitleAndArtist() {
        XCTAssertEqual(SpotifyAdapter.songQuery("Play Blinding Lights by The Weeknd on Spotify"), "Blinding Lights by The Weeknd")
        XCTAssertEqual(SpotifyAdapter.songQuery("Put on the song Dreams in Spotify"), "Dreams")
    }

    func testMessagePreflightDoesNotSend() async {
        let result = await MessagesAdapter.prepare("Text +15551234567 saying Running late", workflow: nil)
        XCTAssertTrue(result.success)
        XCTAssertEqual(result.artifacts["message_handle"], "+15551234567")
        XCTAssertEqual(result.artifacts["message_body"], "Running late")
    }

    func testExplicitSpotifyRequestKeepsOnlySpotifyChoices() {
        let tools = ToolEngine().tools
        let selected = JevClient.focusedCandidates(for: "Play Blinding Lights by The Weeknd on Spotify", tools: tools, history: [])
        XCTAssertFalse(selected.isEmpty)
        XCTAssertTrue(selected.allSatisfy { $0.id.hasPrefix("spotify.") })
        let web = JevClient.focusedCandidates(for: "Open spotify.com in the browser", tools: tools, history: [])
        XCTAssertTrue(web.allSatisfy { $0.id.hasPrefix("browser.") })
        let message = JevClient.focusedCandidates(for: "Text Alex saying look at this page", tools: tools, history: [])
        XCTAssertTrue(message.allSatisfy { $0.id.hasPrefix("messages.") })
        let multiStep = JevClient.focusedCandidates(for: "Open Spotify and text Alex saying hi", tools: tools, history: [])
        XCTAssertEqual(multiStep.count, tools.count)
    }

    func testContextualTextRequestsStayWithTextTools() {
        let tools = ToolEngine().tools
        for request in ["Summarize this page", "What does this page say about refunds?", "Explain the selected text"] {
            let selected = JevClient.focusedCandidates(for: request, tools: tools, history: [])
            XCTAssertFalse(selected.isEmpty, request)
            XCTAssertTrue(selected.allSatisfy { $0.id.hasPrefix("text.") }, request)
        }
        XCTAssertEqual(TextSourceHint.explicit(in: "Summarize this page"), .page)
        XCTAssertEqual(TextSourceHint.explicit(in: "Explain the selected text"), .selection)
        XCTAssertEqual(TextSourceHint.explicit(in: "Summarize my clipboard"), .clipboard)
    }

    @MainActor func testSpokenResponseTrimsLongOutput() {
        let response = SpokenResponse.concise(String(repeating: "A long response with useful information. ", count: 20))
        XCTAssertLessThanOrEqual(response.count, 281)
        XCTAssertFalse(response.contains("\n"))
        XCTAssertTrue(response.hasSuffix("."))
    }

    @MainActor func testPiperVoiceDiscoveryAndNaming() throws {
        let output = SpokenResponse()
        let jarvis = try XCTUnwrap(output.availableVoices.first { $0.lastPathComponent == "jarvis-medium.onnx" })
        XCTAssertEqual(SpokenResponse.displayName(for: jarvis), "Jarvis")
        XCTAssertEqual(output.availableVoices.first?.path, jarvis.path)
    }

    @MainActor func testLivePiperNarrationWhenEnabled() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["PIPER_LIVE_TEST"] == "1")
        let output = SpokenResponse()
        output.speak("Jarvis voice check.", force: true)
        for _ in 0..<60 where output.lastAudioBytes == 0 && output.lastError == nil {
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertNil(output.lastError)
        XCTAssertGreaterThan(output.lastAudioBytes, 44)
        output.stop()
    }

    func testLiveContextualJevRoutingWhenEnabled() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["JEV_LIVE_TEST"] == "1")
        let decision = try await JevClient().route(
            transcript: "What does this page say about refunds?",
            context: ["frontmost_app": "Dia", "focused_element": "web page"],
            tools: ToolEngine().tools
        )
        XCTAssertEqual(decision.tool.id, "text.answer")
    }

    func testLiveLocalAnswerWhenEnabled() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["OLLAMA_LIVE_TEST"] == "1")
        let answer = try await OllamaTextClient().generate(
            operation: .answer,
            request: "What is the refund window?",
            source: "Refunds are available within 30 days with a receipt."
        )
        XCTAssertTrue(answer.contains("30"), answer)
    }

    @MainActor func testLiveSpotifyReadOnlyWhenEnabled() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SPOTIFY_LIVE_TEST"] == "1")
        let result = await SpotifyAdapter.execute("spotify.now_playing", transcript: "what is playing on Spotify")
        XCTAssertTrue(result.success, result.summary)
    }

    func testLiveJevRoutesNewCommandsWhenEnabled() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["JEV_LIVE_TEST"] == "1")
        let examples = [
            ("Play Blinding Lights by The Weeknd on Spotify", "spotify.play"),
            ("Text Alex saying I am on my way", "messages.send"),
            ("Send an SMS to +15551234567 saying Running late", "messages.send_sms"),
            ("Go back in the browser", "browser.back"),
            ("Search the web for weather in Berkeley", "browser.search"),
            ("Find the word refund on this page", "browser.find_text"),
            ("Open Spotify", "app.open"),
            ("Click the Save button", "ui.click"),
            ("Type hello into the focused field", "keyboard.type"),
        ]
        for (request, expected) in examples {
            let decision = try await JevClient().route(
                transcript: request,
                context: ["frontmost_app": "Dia", "focused_element": "window"],
                tools: ToolEngine().tools
            )
            XCTAssertEqual(decision.tool.id, expected, request)
            if expected.hasPrefix("messages.send") {
                XCTAssertTrue(decision.shouldConfirm, request)
            } else {
                XCTAssertFalse(decision.shouldConfirm, request)
            }
        }
    }

    func testLiveJevChoosesSecondStepWhenEnabled() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["JEV_LIVE_TEST"] == "1")
        let completed = WorkflowRecord(toolID: "app.open", title: "Open application", success: true, summary: "Opened Spotify.", output: "")
        let decision = try await JevClient().route(
            transcript: "Open Spotify and then pause it",
            context: ["frontmost_app": "Spotify", "focused_element": "window"],
            tools: ToolEngine().tools,
            history: [completed], step: 1
        )
        XCTAssertEqual(decision.tool.id, "spotify.pause")
    }

    func testRequestTelemetrySumsAllJevCalls() async {
        let telemetry = RequestTelemetry()
        await telemetry.recordJevAttempt()
        await telemetry.recordJevUsage(["usage": ["input_tokens": 296, "output_tokens": 20]])
        await telemetry.recordJevAttempt()
        await telemetry.recordJevUsage(["usage": ["input_tokens": 412, "output_tokens": 67]])
        let metrics = await telemetry.snapshot()
        XCTAssertEqual(metrics.jevCalls, 2)
        XCTAssertEqual(metrics.jevInputTokens, 708)
        XCTAssertEqual(metrics.estimatedJevCostUSD ?? -1, 708 * RequestTelemetry.jevUSDPerInputToken, accuracy: 1e-12)
        XCTAssertTrue(metrics.compactLabel.contains("Jev ~$0.000030"))
    }

    func testRequestTelemetryDoesNotInventCostWhenUsageIsMissing() async {
        let telemetry = RequestTelemetry()
        await telemetry.recordJevAttempt()
        let metrics = await telemetry.snapshot()
        XCTAssertNil(metrics.estimatedJevCostUSD)
        XCTAssertTrue(metrics.compactLabel.contains("Jev unavailable"))
    }

    func testConfirmationWaitIsExcludedFromLatency() async throws {
        let telemetry = RequestTelemetry()
        await telemetry.pauseForConfirmation()
        try await Task.sleep(for: .milliseconds(35))
        let waiting = await telemetry.snapshot()
        XCTAssertLessThan(waiting.latencySeconds, 0.02)
        await telemetry.resumeAfterConfirmation()
        try await Task.sleep(for: .milliseconds(20))
        let resumed = await telemetry.snapshot()
        XCTAssertGreaterThan(resumed.latencySeconds, waiting.latencySeconds)
    }
}
