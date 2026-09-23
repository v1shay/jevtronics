import Contacts
import Foundation

enum MessagesAdapter {
    struct Draft: Equatable {
        let recipient: String
        let body: String
    }

    static func parse(_ request: String, generated: String? = nil) -> Draft? {
        let trimmed = request.trimmingCharacters(in: .whitespacesAndNewlines)
        let patterns = [
            #"(?i)^(?:please\s+)?(?:draft|send|text|message)\s+(?:(?:a|an)\s+(?:text|message|SMS)\s+to\s+|SMS\s+to\s+)?(.+?)\s+(?:a\s+(?:text|message)\s+)?(?:saying|that says|with the message|with the text|the message|the text)\s+(.+)$"#,
            #"(?i)^(?:please\s+)?(?:draft|send|text|message)\s+(?:(?:a|an)\s+(?:text|message|SMS)\s+to\s+|SMS\s+to\s+)?(.+?)\s*:\s*(.+)$"#,
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
                  let recipientRange = Range(match.range(at: 1), in: trimmed),
                  let bodyRange = Range(match.range(at: 2), in: trimmed) else { continue }
            let recipient = String(trimmed[recipientRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            let spokenBody = String(trimmed[bodyRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            let body = generated?.trimmingCharacters(in: .whitespacesAndNewlines) ?? spokenBody
            if !recipient.isEmpty && !body.isEmpty { return Draft(recipient: recipient, body: body) }
        }
        return nil
    }

    static func prepare(_ transcript: String, workflow: WorkflowState?) async -> ToolResult {
        guard let draft = parse(transcript, generated: workflow?.records.last(where: { $0.toolID.hasPrefix("text.") })?.output) else {
            return .init(success: false, summary: "Say ‘text Alex saying I’m on my way’ or use a phone number or email address.")
        }
        guard draft.body.count <= 200 else { return .init(success: false, summary: "The message is too long for the notch preview. Shorten it before sending.") }
        let resolved = await resolve(draft.recipient)
        switch resolved {
        case .failure(let reason): return .init(success: false, summary: reason)
        case .success(let target):
            return .init(
                success: true,
                summary: "Send \(transcript.localizedCaseInsensitiveContains("SMS") ? "SMS " : "")to \(target.label) (\(target.handle)): \(draft.body)",
                artifacts: ["message_handle": target.handle, "message_label": target.label, "message_body": draft.body]
            )
        }
    }

    static func send(workflow: WorkflowState?, sms: Bool = false) -> ToolResult {
        guard let handle = workflow?.artifacts["message_handle"],
              let body = workflow?.artifacts["message_body"],
              !handle.isEmpty, !body.isEmpty else {
            return .init(success: false, summary: "The recipient and message must be reviewed before sending.")
        }
        let script = """
        tell application "Messages"
            set activeService to first service whose service type is \(sms ? "SMS" : "iMessage") and enabled is true
            set targetBuddy to buddy "\(escape(handle))" of activeService
            send "\(escape(body))" to targetBuddy
        end tell
        """
        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)
        if let error {
            return .init(success: false, summary: error[NSAppleScript.errorMessage] as? String ?? "Messages could not send the text.")
        }
        let label = workflow?.artifacts["message_label"] ?? handle
        return .init(success: true, summary: "Handed the message to Messages for \(label). Check Messages for delivery status.")
    }

    private struct Target {
        let label: String
        let handle: String
    }

    private enum Resolution {
        case success(Target)
        case failure(String)
    }

    private static func resolve(_ raw: String) async -> Resolution {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.contains("@") { return .success(Target(label: value, handle: value)) }
        let digits = value.filter(\.isNumber)
        if digits.count >= 10 && value.allSatisfy({ $0.isNumber || "+-(). ".contains($0) }) {
            return .success(Target(label: value, handle: value))
        }
        let store = CNContactStore()
        guard (try? await store.requestAccess(for: .contacts)) == true else {
            return .failure("Contacts permission is needed to resolve \(value). Say the full phone number or email instead.")
        }
        let keys = [CNContactGivenNameKey, CNContactFamilyNameKey, CNContactPhoneNumbersKey, CNContactEmailAddressesKey] as [CNKeyDescriptor]
        do {
            let matches = try store.unifiedContacts(matching: CNContact.predicateForContacts(matchingName: value), keysToFetch: keys)
            let exact = matches.filter {
                ["\($0.givenName) \($0.familyName)", $0.givenName, $0.familyName]
                    .contains { $0.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(value) == .orderedSame }
            }
            guard exact.count == 1, let contact = exact.first else {
                return .failure(matches.isEmpty ? "No contact named \(value) was found." : "Several contacts match \(value). Say the full name or phone number.")
            }
            let mobile = contact.phoneNumbers.filter {
                $0.label == CNLabelPhoneNumberMobile || $0.label == CNLabelPhoneNumberiPhone
            }.map { $0.value.stringValue }
            let phones = contact.phoneNumbers.map { $0.value.stringValue }
            let emails = contact.emailAddresses.map { $0.value as String }
            let preferred = mobile.isEmpty ? (phones.isEmpty ? emails : phones) : mobile
            guard preferred.count == 1, let handle = preferred.first else {
                return .failure(preferred.isEmpty ? "\(value) has no message address." : "\(value) has multiple matching numbers or addresses. Say the exact one to use.")
            }
            return .success(Target(label: "\(contact.givenName) \(contact.familyName)".trimmingCharacters(in: .whitespacesAndNewlines), handle: handle))
        } catch {
            return .failure("Could not look up \(value): \(error.localizedDescription)")
        }
    }

    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\n", with: "\\n")
    }
}
