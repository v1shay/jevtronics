import Foundation

@MainActor
final class WorkflowCoordinator {
    typealias ProgressHandler = (_ step: Int, _ tool: ToolDefinition, _ confidence: Double) -> Void

    private let jev: JevClient
    private let engine: ToolEngine
    private let maxSteps = 8

    init(jev: JevClient, engine: ToolEngine) {
        self.jev = jev
        self.engine = engine
    }

    func start(request: String, context: [String: String], telemetry: RequestTelemetry? = nil, onProgress: ProgressHandler) async -> WorkflowOutcome {
        await advance(state: WorkflowState(request: request, context: context), telemetry: telemetry, onProgress: onProgress)
    }

    func resume(_ pending: PendingWorkflow, telemetry: RequestTelemetry? = nil, onProgress: ProgressHandler) async -> WorkflowOutcome {
        var state = pending.state
        let decision = pending.decision
        onProgress(state.step + 1, decision.tool, decision.confidence)
        let result = await engine.execute(decision.tool, transcript: state.request, workflow: state)
        append(result, decision: decision, to: &state)
        guard result.success else { return .failed(result.summary, state.records) }
        if isSingleAction(state) { return .completed(result, state.records) }
        return await advance(state: state, telemetry: telemetry, onProgress: onProgress)
    }

    private func advance(state initialState: WorkflowState, telemetry: RequestTelemetry?, onProgress: ProgressHandler) async -> WorkflowOutcome {
        var state = initialState
        while state.step < maxSteps {
            do {
                let decision = try await jev.route(
                    transcript: state.request,
                    context: state.context,
                    tools: engine.tools,
                    history: state.records,
                    step: state.step,
                    telemetry: telemetry
                )

                if decision.tool.id == "workflow.finish" {
                    let last = state.records.last
                    let result = ToolResult(
                        success: true,
                        summary: last?.summary ?? "Request completed.",
                        output: last?.output ?? "",
                        artifacts: state.artifacts
                    )
                    return .completed(result, state.records)
                }

                if decision.tool.id == "messages.send" || decision.tool.id == "messages.send_sms" {
                    let prepared = await MessagesAdapter.prepare(state.request, workflow: state)
                    guard prepared.success else { return .failed(prepared.summary, state.records) }
                    if decision.tool.id == "messages.send_sms",
                       !(prepared.artifacts["message_handle"] ?? "").contains(where: \.isNumber) {
                        return .failed("SMS needs a phone number for this contact.", state.records)
                    }
                    prepared.artifacts.forEach { state.artifacts[$0.key] = $0.value }
                    return .confirmation(PendingWorkflow(state: state, decision: decision, preview: prepared.summary))
                }

                if decision.shouldConfirm || needsClickConfirmation(decision.tool, request: state.request) || decision.confidence < 0.60 {
                    return .confirmation(PendingWorkflow(state: state, decision: decision))
                }

                onProgress(state.step + 1, decision.tool, decision.confidence)
                let result = await engine.execute(decision.tool, transcript: state.request, workflow: state)
                append(result, decision: decision, to: &state)
                guard result.success else { return .failed(result.summary, state.records) }

                if isSingleAction(state) { return .completed(result, state.records) }

                if repeatedWithoutProgress(state.records) {
                    return .failed("Jev repeated the same step without making progress, so the workflow was stopped safely.", state.records)
                }
            } catch {
                return .failed(error.localizedDescription, state.records)
            }
        }
        return .failed("The workflow reached its \(maxSteps)-step safety limit.", state.records)
    }

    private func append(_ result: ToolResult, decision: RouteDecision, to state: inout WorkflowState) {
        state.records.append(.init(
            toolID: decision.tool.id,
            title: decision.tool.title,
            success: result.success,
            summary: result.summary,
            output: result.output
        ))
        result.artifacts.forEach { state.artifacts[$0.key] = $0.value }
        state.executedToolIDs.append(decision.tool.id)
        state.step += 1
    }

    private func repeatedWithoutProgress(_ records: [WorkflowRecord]) -> Bool {
        guard records.count >= 2 else { return false }
        let last = records[records.count - 1]
        let prior = records[records.count - 2]
        return last.toolID == prior.toolID && last.output == prior.output && last.summary == prior.summary
    }

    private func isSingleAction(_ state: WorkflowState) -> Bool {
        guard state.step == 1, let id = state.records.last?.toolID else { return false }
        let direct = id.hasPrefix("spotify.") || id.hasPrefix("messages.") || id.hasPrefix("media.") || id.hasPrefix("text.") ||
            id.hasPrefix("app.") || id.hasPrefix("browser.") || id.hasPrefix("ui.") || id.hasPrefix("window.")
        guard direct else { return false }
        return state.request.range(of: #"\b(and|then|after that|also|followed by)\b"#, options: [.regularExpression, .caseInsensitive]) == nil
    }

    private func needsClickConfirmation(_ tool: ToolDefinition, request: String) -> Bool {
        guard tool.id == "ui.click" else { return false }
        return request.range(of: #"\b(delete|remove|send|submit|purchase|buy|pay|transfer|post|publish|confirm)\b"#, options: [.regularExpression, .caseInsensitive]) != nil
    }
}
