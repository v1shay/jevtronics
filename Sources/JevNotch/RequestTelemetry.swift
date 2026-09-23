import Foundation

/// One voice command's wall time and Jev metering, including every routing step.
actor RequestTelemetry {
    // TypeSafe's published Jev 1.13 price: $0.042 per million input tokens.
    static let jevUSDPerInputToken = 0.042 / 1_000_000.0

    private let startedAt = ProcessInfo.processInfo.systemUptime
    private var jevAttempts = 0
    private var meteredCalls = 0
    private var inputTokens = 0
    private var pausedAt: TimeInterval?
    private var pausedSeconds: TimeInterval = 0

    func recordJevAttempt() { jevAttempts += 1 }

    func recordJevUsage(_ response: [String: Any]) {
        guard let usage = response["usage"] as? [String: Any],
              let tokens = usage["input_tokens"] as? Int,
              tokens >= 0 else { return }
        inputTokens += tokens
        meteredCalls += 1
    }

    func pauseForConfirmation() {
        if pausedAt == nil { pausedAt = ProcessInfo.processInfo.systemUptime }
    }

    func resumeAfterConfirmation() {
        guard let pausedAt else { return }
        pausedSeconds += ProcessInfo.processInfo.systemUptime - pausedAt
        self.pausedAt = nil
    }

    func snapshot() -> RequestMetricsSnapshot {
        let now = pausedAt ?? ProcessInfo.processInfo.systemUptime
        return RequestMetricsSnapshot(
            latencySeconds: max(0, now - startedAt - pausedSeconds),
            estimatedJevCostUSD: jevAttempts == meteredCalls
                ? Double(inputTokens) * Self.jevUSDPerInputToken
                : nil,
            jevInputTokens: inputTokens,
            jevCalls: jevAttempts
        )
    }
}
