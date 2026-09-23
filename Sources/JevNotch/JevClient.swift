import Foundation

actor JevClient {
    private let endpoint = URL(string: "https://api.typesafe.ai/v1/systemone")!

    func route(
        transcript: String,
        context: [String: String],
        tools: [ToolDefinition],
        history: [WorkflowRecord] = [],
        step: Int = 0,
        telemetry: RequestTelemetry? = nil
    ) async throws -> RouteDecision {
        guard let key = KeychainStore.readAPIKey(), !key.isEmpty else { throw NotchError.missingAPIKey }

        let completed = history.isEmpty
            ? "No tools have run yet."
            : history.enumerated().map { "\($0.offset + 1). \($0.element.compactDescription)" }.joined(separator: "\n")
        let state: [String: Any] = [
            "request": transcript,
            "frontmost_app": context["frontmost_app"] ?? "unknown",
            "focused_element": context["focused_element"] ?? "unknown",
            "workflow_step": step + 1,
            "completed_steps": completed,
            "instruction": "Select exactly one registered action for the NEXT step only. Use workflow.finish only when the complete user request is satisfied by the completed steps. Never ask a text generator to choose tools. Prefer observation before mutation and prefer read-only actions when ambiguous. Avoid repeating an action unless its prior result shows that repetition is necessary."
        ]

        var candidates = Self.focusedCandidates(for: transcript, tools: tools, history: history)
        var domainConfidence = 1.0
        if candidates.count == tools.count {
            let grouped = Dictionary(grouping: tools, by: { $0.id.split(separator: ".").first.map(String.init) ?? "other" })
            let descriptions = Dictionary(uniqueKeysWithValues: grouped.map { domain, members in
                (domain, "\(domain) actions: \(members.map(\.title).joined(separator: ", "))")
            })
            let domainBody: [String: Any] = [
                "model": "jev-latest",
                "state": state,
                "questions": ["domain": [
                    "type": "choice",
                    "instructions": "Select the action family for the NEXT step only. Select workflow only after all requested actions succeeded.",
                    "criteria": descriptions,
                ]],
            ]
            let domainRoot = try await request(domainBody, key: key, telemetry: telemetry)
            guard let answers = domainRoot["answers"] as? [String: Any],
                  let answer = answers["domain"] as? [String: Any],
                  let selected = answer["choice"] as? String,
                  let selectedTools = grouped[selected] else { throw NotchError.invalidResponse }
            candidates = selectedTools
            domainConfidence = answer["confidence"] as? Double ?? 0
        }
        let criteria = Dictionary(uniqueKeysWithValues: candidates.map { ($0.id, $0.routingDescription) })
        let body: [String: Any] = [
            "model": "jev-latest",
            "state": state,
            "questions": [
                "tool": [
                    "type": "choice",
                    "instructions": "Given the original request and completed-step results, which registered action should run next? 'Text someone saying ...' means messages.send; explicit 'SMS' means messages.send_sms. Use messages.draft only when the user explicitly asks to draft or compose without sending. Choose workflow.finish only if no further action is needed.",
                    "criteria": criteria,
                ],
                "confirm": [
                    "type": "noul",
                    "instructions": "Does the selected action send a message, delete data, run a shell command, quit an app with possible unsaved work, purchase, publish, submit, or make another consequential change? Reversible playback, navigation, ordinary button clicks, and typing without submission do not need confirmation.",
                    "criteria": ["true": "Consequential action requires confirmation", "false": "Read-only or reversible action"],
                ],
            ],
        ]

        let root = try await request(body, key: key, telemetry: telemetry)
        guard let answers = root["answers"] as? [String: Any],
              let toolAnswer = answers["tool"] as? [String: Any],
              let toolID = toolAnswer["choice"] as? String,
              let tool = candidates.first(where: { $0.id == toolID }) else {
            throw NotchError.invalidResponse
        }
        let confidence = min(domainConfidence, toolAnswer["confidence"] as? Double ?? 0)
        let confirmAnswer = answers["confirm"] as? [String: Any]
        let modelConfirmation = (confirmAnswer?["noul"] as? Double ?? 0) >= 0.62
        let shouldConfirm = tool.risk == .consequential || modelConfirmation
        return RouteDecision(tool: tool, confidence: confidence, shouldConfirm: shouldConfirm)
    }

    private func request(_ body: [String: Any], key: String, telemetry: RequestTelemetry?) async throws -> [String: Any] {
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = 12
        urlRequest.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)
        await telemetry?.recordJevAttempt()
        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        if let parsed { await telemetry?.recordJevUsage(parsed) }
        guard let http = response as? HTTPURLResponse else { throw NotchError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let message = parsed?["detail"] as? String
            throw NotchError.failed(message ?? "Jev request failed with HTTP \(http.statusCode).")
        }
        guard let root = parsed else { throw NotchError.invalidResponse }
        return root
    }

    static func focusedCandidates(for transcript: String, tools: [ToolDefinition], history: [WorkflowRecord]) -> [ToolDefinition] {
        guard history.isEmpty else { return tools }
        let request = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard request.range(of: #"\b(and|then|also|after that|followed by)\b"#, options: [.regularExpression, .caseInsensitive]) == nil else { return tools }
        func matches(_ pattern: String) -> Bool {
            request.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
        }
        let prefix: String?
        if matches(#"^(please\s+)?(open|launch|activate|switch to|hide|quit)\s+(the\s+)?(spotify|dia|safari|chrome|finder|messages|calendar|notes|music|mail|terminal|xcode)(\s+app)?[.!?]?$"#) {
            prefix = "app."
        } else if matches(#"^(please\s+)?(text|message|draft (a )?(text|message)|send (a|an)?\s*(text|message|SMS))\b"#) {
            prefix = "messages."
        } else if (matches(#"\b(summarize|explain|rewrite|rephrase|extract action items|answer)\b"#) && TextSourceHint.explicit(in: request) != nil)
                    || matches(#"^(what|which|who|when|where|how)\b.*\b(this|current)\s+(page|article|tab|selection|text)\b"#) {
            prefix = "text."
        } else if matches(#"\b(browser|web|website|tab|page|url)\b|\.[a-z]{2,}(\/|\b)"#) {
            prefix = "browser."
        } else if matches(#"\bspotify\b"#) {
            prefix = "spotify."
        } else if matches(#"^(please\s+)?(click|press|select)\s+"#) {
            prefix = "ui."
        } else if matches(#"^(please\s+)?(type|insert|paste|copy|cut|undo|redo)\s+"#) {
            prefix = "keyboard."
        } else {
            prefix = nil
        }
        guard let prefix else { return tools }
        let selected = tools.filter { $0.id.hasPrefix(prefix) }
        return selected.isEmpty ? tools : selected
    }

}
