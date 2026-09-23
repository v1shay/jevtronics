import AppKit
import Foundation

@MainActor
enum SpotifyAdapter {
    static func execute(_ toolID: String, transcript: String) async -> ToolResult {
        guard FileManager.default.fileExists(atPath: "/Applications/Spotify.app") else {
            return fail("Spotify is not installed in Applications.")
        }
        switch toolID {
        case "spotify.play": return await play(transcript)
        case "spotify.resume": return await command("play", expected: "playing", summary: "Resumed Spotify.")
        case "spotify.pause": return await command("pause", expected: "paused", summary: "Paused Spotify.")
        case "spotify.next": return await command("next track", expected: nil, summary: "Skipped to the next Spotify track.")
        case "spotify.previous": return await command("previous track", expected: nil, summary: "Returned to the previous Spotify track.")
        case "spotify.now_playing":
            guard let state = currentState() else { return fail("Spotify has no current track.") }
            return .init(success: true, summary: "Spotify is \(state.state): \(state.name) by \(state.artist).")
        default: return fail("That Spotify command is unavailable.")
        }
    }

    static func songQuery(_ transcript: String) -> String? {
        var value = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        value = value.replacingOccurrences(of: #"(?i)^(?:please\s+)?(?:play|put on|start)\s+(?:the\s+song\s+|the\s+track\s+|song\s+)?"#, with: "", options: .regularExpression)
        value = value.replacingOccurrences(of: #"(?i)\s+(?:on|in|using)\s+spotify[.!?]?$"#, with: "", options: .regularExpression)
        value = value.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        return value.isEmpty ? nil : value
    }

    private static func play(_ transcript: String) async -> ToolResult {
        guard let query = songQuery(transcript) else { return fail("Say a song title and optionally an artist.") }
        let uri: String
        let expectedName: String?
        if let range = query.range(of: #"spotify:track:[A-Za-z0-9]{22}"#, options: .regularExpression) {
            uri = String(query[range]); expectedName = nil
        } else {
            let parts = query.range(of: " by ", options: .caseInsensitive)
            let requestedTitle = parts.map { String(query[..<$0.lowerBound]) } ?? query
            let requestedArtist = parts.map { String(query[$0.upperBound...]) }
            let results: [SpotifyOAuth.Track]
            do { results = try await SpotifyOAuth.shared.searchTracks(query) }
            catch { return fail(error.localizedDescription) }
            let exact = results.filter {
                normalize($0.name) == normalize(requestedTitle) &&
                (requestedArtist == nil || normalize($0.artist).contains(normalize(requestedArtist!)))
            }
            if requestedArtist == nil && Set(exact.map { normalize($0.artist) }).count > 1 {
                let options = exact.prefix(3).map { "\($0.name) by \($0.artist)" }.joined(separator: "; ")
                return fail("Several artists have that song: \(options). Say the artist too.")
            }
            guard let selected = exact.first else {
                let options = results.prefix(3).map { "\($0.name) by \($0.artist)" }.joined(separator: "; ")
                return fail(options.isEmpty ? "Spotify found no song matching \(query)." : "No exact song match. Spotify found: \(options). Say the title and artist.")
            }
            uri = selected.uri
            expectedName = selected.name
        }
        let script = "tell application \"Spotify\" to play track \"\(uri)\""
        if let error = run(script).error { return fail("Spotify could not play the track: \(error)") }
        for _ in 0..<5 {
            if let state = currentState(), state.uri == uri, state.state == "playing" {
                return .init(success: true, summary: "Playing \(state.name) by \(state.artist) on Spotify.")
            }
            try? await Task.sleep(for: .milliseconds(250))
        }
        let label = expectedName ?? "the requested track"
        return fail("Spotify accepted \(label), but its current track did not confirm playback. Check the Spotify player or account.")
    }

    private static func command(_ instruction: String, expected: String?, summary: String) async -> ToolResult {
        let before = currentState()
        if let error = run("tell application \"Spotify\" to \(instruction)").error { return fail(error) }
        for _ in 0..<5 {
            if let after = currentState(),
               (expected == nil || after.state == expected),
               (instruction != "next track" && instruction != "previous track" || before?.uri != after.uri) {
                return .init(success: true, summary: "\(summary) \(after.name) by \(after.artist).")
            }
            try? await Task.sleep(for: .milliseconds(200))
        }
        return fail("Spotify did not confirm the playback change.")
    }

    private struct State {
        let uri: String
        let name: String
        let artist: String
        let state: String
    }

    private static func currentState() -> State? {
        let script = """
        tell application "Spotify"
            if player state is stopped then return ""
            set t to current track
            return (id of t) & "|||" & (name of t) & "|||" & (artist of t) & "|||" & (player state as text)
        end tell
        """
        let result = run(script)
        guard let text = result.value else { return nil }
        let parts = text.components(separatedBy: "|||")
        guard parts.count == 4 else { return nil }
        return State(uri: parts[0], name: parts[1], artist: parts[2], state: parts[3].lowercased())
    }

    private static func run(_ source: String) -> (value: String?, error: String?) {
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        return (result?.stringValue, error?[NSAppleScript.errorMessage] as? String)
    }

    private static func normalize(_ text: String) -> String {
        text.lowercased().folding(options: [.diacriticInsensitive], locale: .current)
            .filter { $0.isLetter || $0.isNumber }
    }

    private static func fail(_ message: String) -> ToolResult { .init(success: false, summary: message) }
}
