import Foundation

/// A deliberately narrow local text worker. It never receives the tool catalog,
/// never returns tool calls, and has no access to native executors.
actor OllamaTextClient {
    static let defaultModel = "gemma3:4b"

    private let endpoint = URL(string: "http://127.0.0.1:11434/api/generate")!
    private let tagsEndpoint = URL(string: "http://127.0.0.1:11434/api/tags")!
    private let model: String
    private var ownedServer: Process?

    init(model: String = OllamaTextClient.defaultModel) {
        self.model = model
    }

    func isAvailable() async -> Bool {
        var request = URLRequest(url: tagsEndpoint)
        request.timeoutInterval = 1.5
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              http.statusCode == 200,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = root["models"] as? [[String: Any]] else { return false }
        return models.contains { ($0["name"] as? String) == model || ($0["model"] as? String) == model }
    }

    func ensureAvailable() async -> Bool {
        if await isAvailable() { return true }
        guard ownedServer == nil,
              let executable = ["/opt/homebrew/bin/ollama", "/usr/local/bin/ollama"].first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            return false
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["serve"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            ownedServer = process
        } catch { return false }
        for _ in 0..<24 {
            try? await Task.sleep(for: .milliseconds(250))
            if await isAvailable() { return true }
            if !process.isRunning { return false }
        }
        return false
    }

    func generate(operation: TextOperation, request: String, source: String) async throws -> String {
        let system = """
        You are a private local text transformation worker inside a macOS automation app.
        You may only produce text. You do not choose tools, plan actions, call functions,
        claim that actions occurred, or output tool-call JSON. Follow the requested text
        operation using only the supplied source. Return only the finished content.
        Never invent facts absent from the source. If required information is missing,
        plainly state what information is missing.
        """
        let prompt = """
        TEXT OPERATION: \(operation.instruction)
        USER REQUEST: \(request)

        SOURCE TEXT:
        \(String(source.prefix(24_000)))
        """
        let body: [String: Any] = [
            "model": model,
            "system": system,
            "prompt": prompt,
            "stream": false,
            "keep_alive": "30m",
            "options": ["temperature": 0.2, "num_predict": operation == .answer ? 240 : 900],
        ]
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = 75
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else { throw NotchError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw NotchError.failed("Ollama returned HTTP \(http.statusCode).")
        }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = root["response"] as? String,
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NotchError.invalidResponse
        }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func prewarm() async {
        guard await ensureAvailable() else { return }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 40
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "model": model, "prompt": "", "stream": false, "keep_alive": "30m",
        ])
        _ = try? await URLSession.shared.data(for: request)
    }
}

enum TextOperation: String, CaseIterable {
    case generate
    case rewrite
    case summarize
    case answer
    case extractActions
    case draftEmail

    var instruction: String {
        switch self {
        case .generate: "Generate the requested prose from the supplied source."
        case .rewrite: "Rewrite the source according to the user's wording and preserve its facts."
        case .summarize: "Produce a concise, useful summary of the source."
        case .answer: "Answer the user's question using only the supplied source. If the source does not support an answer, say so plainly. Keep the answer brief unless the user asks for detail."
        case .extractActions: "Extract concrete action items, owners, and dates that are explicitly supported by the source."
        case .draftEmail: "Draft only the email body requested by the user. Do not send it and do not add unsupported details."
        }
    }
}
