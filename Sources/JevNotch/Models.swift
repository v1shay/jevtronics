import Foundation

enum NotchPhase: String, Codable {
    case idle, listening, routing, executing, success, error, confirm
}

struct UIState: Codable {
    var phase: NotchPhase
    var transcript = ""
    var detail = ""
    var level: Double = 0
    var expanded = true
    var tool = ""
    var confidence: Double = 0
    var needsConfirmation = false
    var requestMetrics: RequestMetricsSnapshot?
}

struct RequestMetricsSnapshot: Codable, Equatable {
    let latencySeconds: Double
    let estimatedJevCostUSD: Double?
    let jevInputTokens: Int
    let jevCalls: Int

    var compactLabel: String {
        let duration = latencySeconds < 1
            ? "\(Int((latencySeconds * 1_000).rounded())) ms"
            : String(format: "%.2f s", latencySeconds)
        let cost: String
        if let estimatedJevCostUSD {
            cost = estimatedJevCostUSD == 0
                ? "$0"
                : String(format: "~$%.6f", estimatedJevCostUSD)
        } else {
            cost = "unavailable"
        }
        return "\(duration)  ·  Jev \(cost)"
    }
}

enum ToolRisk: String, Codable {
    case read, reversible, consequential
}

struct ToolDefinition: Codable, Hashable {
    let id: String
    let title: String
    let description: String
    let risk: ToolRisk

    var routingDescription: String {
        "\(title). \(description) Risk: \(risk.rawValue)."
    }
}

struct RouteDecision {
    let tool: ToolDefinition
    let confidence: Double
    let shouldConfirm: Bool
}

struct ToolResult {
    let success: Bool
    let summary: String
    var output: String = ""
    var artifacts: [String: String] = [:]
}

struct WorkflowRecord: Codable, Hashable {
    let toolID: String
    let title: String
    let success: Bool
    let summary: String
    let output: String

    var compactDescription: String {
        let value = output.isEmpty ? summary : output
        return "\(toolID): \(String(value.prefix(900)))"
    }
}

struct WorkflowState {
    let request: String
    let context: [String: String]
    var records: [WorkflowRecord] = []
    var artifacts: [String: String] = [:]
    var executedToolIDs: [String] = []
    var step = 0

    var latestText: String {
        records.last(where: { !$0.output.isEmpty })?.output ?? request
    }
}

struct PendingWorkflow {
    var state: WorkflowState
    let decision: RouteDecision
    var preview: String = ""
}

enum WorkflowOutcome {
    case completed(ToolResult, [WorkflowRecord])
    case confirmation(PendingWorkflow)
    case failed(String, [WorkflowRecord])
}

enum NotchError: LocalizedError {
    case missingAPIKey
    case invalidResponse
    case unavailable(String)
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: return "Add a TypeSafe API key in Jev Notch settings or the Keychain."
        case .invalidResponse: return "Jev returned an unreadable decision."
        case .unavailable(let message), .failed(let message): return message
        }
    }
}
