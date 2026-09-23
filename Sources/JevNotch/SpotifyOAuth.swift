import AppKit
import CryptoKit
import Foundation
import Network

actor SpotifyOAuth {
    static let shared = SpotifyOAuth()
    static let redirectURI = "http://127.0.0.1:43879/callback"
    static let clientIDKey = "spotify-client-id"

    struct Track {
        let name: String
        let artist: String
        let uri: String
    }

    private struct Token: Codable {
        var accessToken: String
        var refreshToken: String
        var expiresAt: Date
    }

    private let service = "com.jevnotch.spotify"
    private var cachedToken: Token?

    static var clientID: String? {
        let value = UserDefaults.standard.string(forKey: clientIDKey)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? nil : value
    }

    func connect() async throws {
        guard let clientID = Self.clientID else {
            throw NotchError.unavailable("Set a Spotify Client ID from the Jev Notch menu first.")
        }
        let verifier = randomVerifier()
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncodedString()
        let state = UUID().uuidString
        var components = URLComponents(string: "https://accounts.spotify.com/authorize")!
        components.queryItems = [
            .init(name: "client_id", value: clientID),
            .init(name: "response_type", value: "code"),
            .init(name: "redirect_uri", value: Self.redirectURI),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "code_challenge", value: challenge),
            .init(name: "state", value: state),
        ]
        let authURL = components.url!
        let code = try await callbackCode(expectedState: state, authURL: authURL)
        let token = try await exchange([
            "grant_type": "authorization_code", "code": code,
            "redirect_uri": Self.redirectURI, "client_id": clientID,
            "code_verifier": verifier,
        ], previousRefreshToken: nil)
        try save(token)
    }

    func searchTracks(_ query: String) async throws -> [Track] {
        let accessToken = try await validToken().accessToken
        var components = URLComponents(string: "https://api.spotify.com/v1/search")!
        components.queryItems = [
            .init(name: "q", value: query),
            .init(name: "type", value: "track"),
            .init(name: "limit", value: "6"),
        ]
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 8
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw NotchError.invalidResponse }
        if http.statusCode == 429 {
            throw NotchError.unavailable("Spotify is rate limiting searches. Try again shortly.")
        }
        if http.statusCode == 401 {
            cachedToken = nil
            throw NotchError.unavailable("Spotify authorization expired. Use Connect Spotify in the menu bar.")
        }
        guard http.statusCode == 200 else {
            throw NotchError.unavailable("Spotify search returned HTTP \(http.statusCode).")
        }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tracks = root["tracks"] as? [String: Any],
              let items = tracks["items"] as? [[String: Any]] else { throw NotchError.invalidResponse }
        return items.compactMap { item in
            guard let name = item["name"] as? String,
                  let uri = item["uri"] as? String,
                  let artists = item["artists"] as? [[String: Any]] else { return nil }
            let artist = artists.compactMap { $0["name"] as? String }.joined(separator: ", ")
            return Track(name: name, artist: artist, uri: uri)
        }
    }

    private func validToken() async throws -> Token {
        if cachedToken == nil,
           let stored = KeychainStore.read(service: service, account: "token"),
           let data = stored.data(using: .utf8) {
            cachedToken = try? JSONDecoder().decode(Token.self, from: data)
        }
        guard let token = cachedToken else {
            throw NotchError.unavailable("Connect Spotify from the Jev Notch menu bar first.")
        }
        if token.expiresAt > Date().addingTimeInterval(60) { return token }
        guard let clientID = Self.clientID else { throw NotchError.unavailable("Set the Spotify Client ID again.") }
        let refreshed = try await exchange([
            "grant_type": "refresh_token", "refresh_token": token.refreshToken, "client_id": clientID,
        ], previousRefreshToken: token.refreshToken)
        try save(refreshed)
        return refreshed
    }

    private func exchange(_ parameters: [String: String], previousRefreshToken: String?) async throws -> Token {
        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var form = URLComponents()
        form.queryItems = parameters.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        request.httpBody = Data((form.percentEncodedQuery ?? "").utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = object["access_token"] as? String,
              let refreshToken = (object["refresh_token"] as? String) ?? previousRefreshToken,
              let expiresIn = object["expires_in"] as? Int else {
            throw NotchError.unavailable("Spotify authorization failed. Verify the Client ID and registered redirect URI.")
        }
        return Token(accessToken: accessToken, refreshToken: refreshToken, expiresAt: Date().addingTimeInterval(TimeInterval(expiresIn)))
    }

    private func save(_ token: Token) throws {
        let data = try JSONEncoder().encode(token)
        try KeychainStore.save(String(decoding: data, as: UTF8.self), service: service, account: "token")
        cachedToken = token
    }

    private func callbackCode(expectedState: String, authURL: URL) async throws -> String {
        let listener = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: 43879)!)
        let queue = DispatchQueue(label: "com.jevnotch.spotify.callback")
        return try await withCheckedThrowingContinuation { continuation in
            let gate = SpotifyCallbackGate(listener: listener, continuation: continuation)
            listener.newConnectionHandler = { connection in
                connection.start(queue: queue)
                connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, _, _ in
                    let text = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                    let firstLine = text.components(separatedBy: "\r\n").first ?? ""
                    let path = firstLine.split(separator: " ").dropFirst().first.map(String.init) ?? ""
                    let url = URLComponents(string: "http://127.0.0.1\(path)")
                    let state = url?.queryItems?.first(where: { $0.name == "state" })?.value
                    let code = url?.queryItems?.first(where: { $0.name == "code" })?.value
                    let valid = url?.path == "/callback" && state == expectedState && code != nil
                    let body = valid ? "Spotify connected. You can return to Jev Notch." : "Spotify connection was not completed."
                    let status = valid ? "200 OK" : "400 Bad Request"
                    let response = "HTTP/1.1 \(status)\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
                    connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
                    if let code, valid { gate.finish(.success(code)) }
                    else if url?.path == "/callback" && state == expectedState {
                        gate.finish(.failure(NotchError.unavailable("Spotify authorization was cancelled.")))
                    }
                }
            }
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    Task { @MainActor in _ = NSWorkspace.shared.open(authURL) }
                case .failed(let error): gate.finish(.failure(error))
                default: break
                }
            }
            listener.start(queue: queue)
            queue.asyncAfter(deadline: .now() + 120) {
                gate.finish(.failure(NotchError.unavailable("Spotify connection timed out.")))
            }
        }
    }

    private func randomVerifier() -> String {
        (0..<32).map { _ in UInt8.random(in: 0...255) }.withUnsafeBufferPointer { Data(buffer: $0) }.base64URLEncodedString()
    }
}

private final class SpotifyCallbackGate: @unchecked Sendable {
    private let lock = NSLock()
    private var finished = false
    private let listener: NWListener
    private let continuation: CheckedContinuation<String, Error>

    init(listener: NWListener, continuation: CheckedContinuation<String, Error>) {
        self.listener = listener
        self.continuation = continuation
    }

    func finish(_ result: Result<String, Error>) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
        lock.unlock()
        listener.cancel()
        continuation.resume(with: result)
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
