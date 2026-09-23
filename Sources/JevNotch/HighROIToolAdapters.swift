import AppKit
import ApplicationServices
import Contacts
import EventKit
import Foundation

enum HighROIToolAdapters {
    static func execute(_ toolID: String, transcript: String, workflow: WorkflowState?) async -> ToolResult {
        switch toolID {
        case "calendar.today": return await calendarToday()
        case "calendar.create": return await createCalendarEvent(from: transcript)
        case "reminder.list": return await listReminders()
        case "reminder.create": return await createReminder(from: transcript)
        case "notes.search": return searchNotes(from: transcript)
        case "notes.create": return createNote(from: transcript, workflow: workflow)
        case "email.search": return searchMail(from: transcript)
        case "email.draft": return draftMail(from: transcript, workflow: workflow)
        case "contact.search": return await searchContacts(from: transcript)
        case "window.tile_left": return tileWindow(left: true)
        case "window.tile_right": return tileWindow(left: false)
        default: return fail("That adapter is not implemented.")
        }
    }

    private static func calendarToday() async -> ToolResult {
        let store = EKEventStore()
        guard await requestEvents(store) else { return fail("Calendar permission is required.") }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        let events = store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: nil))
        let formatter = DateFormatter(); formatter.timeStyle = .short
        let lines = events.prefix(30).map { "\(formatter.string(from: $0.startDate)) — \($0.title ?? "Untitled")" }
        let value = lines.isEmpty ? "No events today." : lines.joined(separator: "\n")
        return ok(value, output: value)
    }

    private static func createCalendarEvent(from transcript: String) async -> ToolResult {
        let store = EKEventStore()
        guard await requestEvents(store) else { return fail("Calendar permission is required.") }
        guard let start = detectedDate(in: transcript) else {
            return fail("Include an explicit date and time, such as ‘tomorrow at 2 PM’.")
        }
        guard let calendar = store.defaultCalendarForNewEvents else { return fail("No writable default calendar is available.") }
        let title = cleanedTitle(transcript, removing: ["create calendar event", "add calendar event", "schedule", "calendar", "event"])
        let event = EKEvent(eventStore: store)
        event.calendar = calendar
        event.title = title.isEmpty ? "New event" : title
        event.startDate = start
        event.endDate = Calendar.current.date(byAdding: .hour, value: 1, to: start)!
        do {
            try store.save(event, span: .thisEvent, commit: true)
            return ok("Created “\(event.title ?? "New event")” for \(start.formatted(date: .abbreviated, time: .shortened)).", artifacts: ["calendar_event_id": event.eventIdentifier ?? ""])
        } catch { return fail("Calendar could not save the event: \(error.localizedDescription)") }
    }

    private static func listReminders() async -> ToolResult {
        let store = EKEventStore()
        guard await requestReminders(store) else { return fail("Reminders permission is required.") }
        let reminders: [EKReminder] = await withCheckedContinuation { continuation in
            store.fetchReminders(matching: store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)) {
                continuation.resume(returning: $0 ?? [])
            }
        }
        let lines = reminders.prefix(30).map { reminder in
            let due = reminder.dueDateComponents?.date?.formatted(date: .abbreviated, time: .shortened)
            return due.map { "\(reminder.title ?? "Untitled") — \($0)" } ?? (reminder.title ?? "Untitled")
        }
        let value = lines.isEmpty ? "No incomplete reminders." : lines.joined(separator: "\n")
        return ok(value, output: value)
    }

    private static func createReminder(from transcript: String) async -> ToolResult {
        let store = EKEventStore()
        guard await requestReminders(store) else { return fail("Reminders permission is required.") }
        guard let calendar = store.defaultCalendarForNewReminders() else { return fail("No writable reminder list is available.") }
        let reminder = EKReminder(eventStore: store)
        reminder.calendar = calendar
        let title = cleanedTitle(transcript, removing: ["create reminder", "add reminder", "remind me to", "reminder"])
        reminder.title = title.isEmpty ? transcript : title
        if let due = detectedDate(in: transcript) {
            reminder.dueDateComponents = Calendar.current.dateComponents(in: .current, from: due)
        }
        do {
            try store.save(reminder, commit: true)
            return ok("Created reminder “\(reminder.title ?? "Reminder")”.", artifacts: ["reminder_id": reminder.calendarItemIdentifier])
        } catch { return fail("Reminders could not save the item: \(error.localizedDescription)") }
    }

    private static func searchNotes(from transcript: String) -> ToolResult {
        let query = cleanedTitle(transcript, removing: ["search notes for", "find note", "search notes", "notes"])
        guard !query.isEmpty else { return fail("Say what to search for in Notes.") }
        let escaped = appleScriptString(query)
        let script = """
        tell application "Notes"
            set foundItems to {}
            repeat with n in notes
                if (name of n contains "\(escaped)") or (body of n contains "\(escaped)") then
                    set end of foundItems to name of n
                    if (count of foundItems) is 20 then exit repeat
                end if
            end repeat
            return foundItems
        end tell
        """
        return runAppleScript(script, success: "Searched Notes.")
    }

    private static func createNote(from transcript: String, workflow: WorkflowState?) -> ToolResult {
        let body = workflow?.records.last(where: { !$0.output.isEmpty })?.output ?? transcript
        let title = cleanedTitle(transcript, removing: ["create note", "make a note", "note"])
        let safeTitle = appleScriptString(String((title.isEmpty ? "Jev Note" : title).prefix(120)))
        let safeBody = appleScriptString(body)
        let script = """
        tell application "Notes"
            tell default account
                make new note at default folder with properties {name:"\(safeTitle)", body:"\(safeBody)"}
            end tell
        end tell
        """
        return runAppleScript(script, success: "Created a note in Apple Notes.")
    }

    private static func searchMail(from transcript: String) -> ToolResult {
        let query = cleanedTitle(transcript, removing: ["search email for", "search mail for", "find email", "search email", "email"])
        guard !query.isEmpty else { return fail("Say what to search for in Mail.") }
        let escaped = appleScriptString(query)
        let script = """
        tell application "Mail"
            set foundItems to {}
            set recentMessages to messages 1 thru (min of {50, count of messages of inbox}) of inbox
            repeat with m in recentMessages
                if (subject of m contains "\(escaped)") or (sender of m contains "\(escaped)") then
                    set end of foundItems to ((sender of m) & " — " & (subject of m))
                    if (count of foundItems) is 20 then exit repeat
                end if
            end repeat
            return foundItems
        end tell
        """
        return runAppleScript(script, success: "Searched recent email.")
    }

    private static func draftMail(from transcript: String, workflow: WorkflowState?) -> ToolResult {
        guard let address = firstEmail(in: transcript) ?? workflow?.artifacts["email_address"] else {
            return fail("Include the recipient’s full email address so the draft cannot be misaddressed.")
        }
        let body = workflow?.records.last(where: { $0.toolID.hasPrefix("text.") && !$0.output.isEmpty })?.output
            ?? workflow?.latestText
            ?? transcript
        let subject = extractSubject(from: transcript) ?? "Message from Jev"
        let script = """
        tell application "Mail"
            set newMessage to make new outgoing message with properties {subject:"\(appleScriptString(subject))", content:"\(appleScriptString(body))", visible:true}
            tell newMessage to make new to recipient at end of to recipients with properties {address:"\(appleScriptString(address))"}
            activate
        end tell
        """
        return runAppleScript(script, success: "Created a visible Mail draft to \(address). Review it before sending.")
    }

    private static func searchContacts(from transcript: String) async -> ToolResult {
        let store = CNContactStore()
        let allowed = (try? await store.requestAccess(for: .contacts)) ?? false
        guard allowed else { return fail("Contacts permission is required.") }
        let query = cleanedTitle(transcript, removing: ["find contact", "search contacts for", "contact", "find"])
        guard !query.isEmpty else { return fail("Say which contact to find.") }
        let keys = [CNContactGivenNameKey, CNContactFamilyNameKey, CNContactEmailAddressesKey] as [CNKeyDescriptor]
        do {
            let contacts = try store.unifiedContacts(matching: CNContact.predicateForContacts(matchingName: query), keysToFetch: keys)
            let lines = contacts.prefix(15).map { contact in
                let name = [contact.givenName, contact.familyName].filter { !$0.isEmpty }.joined(separator: " ")
                let addresses = contact.emailAddresses.map { $0.value as String }.joined(separator: ", ")
                return addresses.isEmpty ? name : "\(name): \(addresses)"
            }
            let value = lines.isEmpty ? "No matching contacts." : lines.joined(separator: "\n")
            let firstAddress = contacts.first?.emailAddresses.first?.value as String?
            return ok(value, output: value, artifacts: firstAddress.map { ["email_address": $0] } ?? [:])
        } catch { return fail("Contacts search failed: \(error.localizedDescription)") }
    }

    private static func tileWindow(left: Bool) -> ToolResult {
        guard SystemContext.accessibilityTrusted(prompt: true), let window = SystemContext.frontWindow(), let screen = NSScreen.main else {
            return fail("Accessibility permission and a focused window are required.")
        }
        let frame = screen.visibleFrame
        let target = CGRect(x: left ? frame.minX : frame.midX, y: frame.minY, width: frame.width / 2, height: frame.height)
        var position = CGPoint(x: target.minX, y: NSScreen.screens.map(\.frame.maxY).max()! - target.maxY)
        var size = target.size
        guard let positionValue = AXValueCreate(.cgPoint, &position), let sizeValue = AXValueCreate(.cgSize, &size) else {
            return fail("Could not construct the window geometry.")
        }
        let moved = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, positionValue) == .success
        let resized = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue) == .success
        return moved && resized ? ok("Tiled the window to the \(left ? "left" : "right").") : fail("The focused window rejected resizing.")
    }

    private static func requestEvents(_ store: EKEventStore) async -> Bool {
        (try? await store.requestFullAccessToEvents()) ?? false
    }

    private static func requestReminders(_ store: EKEventStore) async -> Bool {
        (try? await store.requestFullAccessToReminders()) ?? false
    }

    private static func detectedDate(in text: String) -> Date? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        return detector.firstMatch(in: text, options: [], range: range)?.date
    }

    private static func firstEmail(in text: String) -> String? {
        let pattern = #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range, in: text) else { return nil }
        return String(text[range])
    }

    private static func extractSubject(from text: String) -> String? {
        guard let range = text.range(of: "subject", options: .caseInsensitive) else { return nil }
        var value = String(text[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        if let body = value.range(of: " body ", options: .caseInsensitive) { value = String(value[..<body.lowerBound]) }
        return value.isEmpty ? nil : String(value.prefix(160))
    }

    private static func cleanedTitle(_ text: String, removing markers: [String]) -> String {
        var result = text
        for marker in markers.sorted(by: { $0.count > $1.count }) {
            result = result.replacingOccurrences(of: marker, with: "", options: .caseInsensitive)
        }
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) {
            let matches = detector.matches(in: result, range: NSRange(result.startIndex..., in: result)).reversed()
            for match in matches where match.resultType == .date {
                if let range = Range(match.range, in: result) { result.removeSubrange(range) }
            }
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    }

    private static func runAppleScript(_ source: String, success: String) -> ToolResult {
        var error: NSDictionary?
        let descriptor = NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error { return fail(error[NSAppleScript.errorMessage] as? String ?? "AppleScript failed.") }
        let value = descriptor?.stringValue ?? ""
        return ok(value.isEmpty ? success : String(value.prefix(300)), output: value)
    }

    private static func appleScriptString(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r\n", with: "\\n")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    private static func ok(_ summary: String, output: String = "", artifacts: [String: String] = [:]) -> ToolResult {
        .init(success: true, summary: summary, output: output, artifacts: artifacts)
    }
    private static func fail(_ summary: String) -> ToolResult { .init(success: false, summary: summary) }
}
