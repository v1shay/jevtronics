import Foundation

enum TextSourceHint: Equatable {
    case page
    case selection
    case clipboard

    static func explicit(in request: String) -> TextSourceHint? {
        func matches(_ pattern: String) -> Bool {
            request.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
        }
        if matches(#"\b(this|current|the)\s+(web\s*)?(page|article|tab)\b|\bwebpage\b"#) { return .page }
        if matches(#"\b(selected|highlighted)\s+(text|paragraph|content)\b|\bselection\b"#) { return .selection }
        if matches(#"\bclipboard\b|\bwhat i copied\b|\bcopied text\b"#) { return .clipboard }
        return nil
    }

    var unavailableMessage: String {
        switch self {
        case .page: "I couldn't read text from the current browser page. Bring Dia, Safari, or Chrome to the front and try again."
        case .selection: "I couldn't read selected text. Select text in the frontmost app and try again."
        case .clipboard: "The clipboard doesn't contain readable text."
        }
    }
}
