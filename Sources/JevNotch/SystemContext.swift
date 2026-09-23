import AppKit
import ApplicationServices

enum SystemContext {
    static func snapshot() -> [String: String] {
        var result = ["frontmost_app": NSWorkspace.shared.frontmostApplication?.localizedName ?? "unknown"]
        let systemWide = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        if AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
           let element = focused {
            let ax = element as! AXUIElement
            var role: CFTypeRef?
            var title: CFTypeRef?
            AXUIElementCopyAttributeValue(ax, kAXRoleAttribute as CFString, &role)
            AXUIElementCopyAttributeValue(ax, kAXTitleAttribute as CFString, &title)
            result["focused_element"] = "\((role as? String) ?? "element") \((title as? String) ?? "")"
        }
        return result
    }

    static func accessibilityTrusted(prompt: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: prompt] as CFDictionary)
    }

    static func frontWindow() -> AXUIElement? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &value) == .success,
              let raw = value else { return nil }
        return (raw as! AXUIElement)
    }

    static func focusedElement() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &value) == .success,
              let raw = value else { return nil }
        return (raw as! AXUIElement)
    }

    static func selectedText() -> String? {
        guard let element = focusedElement() else { return nil }
        var raw: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &raw) == .success,
           let text = raw as? String,
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return text
        }
        return nil
    }

    static func findElement(named query: String, in root: AXUIElement) -> AXUIElement? {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return nil }
        var candidates: [(AXUIElement, Int)] = []
        var visited = 0
        func walk(_ element: AXUIElement, depth: Int) {
            guard depth < 11, visited < 1_000 else { return }
            visited += 1
            var actions: CFArray?
            if AXUIElementCopyActionNames(element, &actions) == .success,
               let names = actions as? [String], names.contains(kAXPressAction) {
                var title: CFTypeRef?; var description: CFTypeRef?
                AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &title)
                AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &description)
                let labels = [title as? String, description as? String].compactMap { $0 }
                if labels.contains(where: { $0.caseInsensitiveCompare(needle) == .orderedSame }) {
                    candidates.append((element, 2))
                } else if labels.contains(where: { $0.localizedCaseInsensitiveContains(needle) }) {
                    candidates.append((element, 1))
                }
            }
            var childrenRaw: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRaw) == .success,
               let children = childrenRaw as? [AXUIElement] {
                for child in children.prefix(180) { walk(child, depth: depth + 1) }
            }
        }
        walk(root, depth: 0)
        let exact = candidates.filter { $0.1 == 2 }
        if exact.count == 1 { return exact[0].0 }
        if exact.count > 1 { return nil }
        return candidates.count == 1 ? candidates[0].0 : nil
    }

    static func visiblePageText(limit: Int = 24_000) -> String {
        guard let root = frontWindow() else { return "" }
        var lines: [String] = []
        var count = 0
        func walk(_ element: AXUIElement, depth: Int) {
            guard depth < 14, count < limit else { return }
            var roleRaw: CFTypeRef?; var valueRaw: CFTypeRef?
            AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRaw)
            let role = roleRaw as? String ?? ""
            if role == "AXStaticText" || role == "AXHeading" || role == "AXLink" {
                AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRaw)
                let value = (valueRaw as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !value.isEmpty {
                    lines.append(String(value.prefix(500)))
                    count += value.count
                }
            }
            var childrenRaw: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRaw) == .success,
               let children = childrenRaw as? [AXUIElement] {
                for child in children.prefix(300) { walk(child, depth: depth + 1) }
            }
        }
        walk(root, depth: 0)
        return lines.joined(separator: "\n")
    }

    static func compactUITree(limit: Int = 80) -> String {
        guard let root = frontWindow() else { return "" }
        var lines: [String] = []
        collectElements(root, depth: 0, limit: limit, lines: &lines)
        return lines.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
    }

    private static func collectElements(_ element: AXUIElement, depth: Int, limit: Int, lines: inout [String]) {
        guard depth < 9, lines.count < limit else { return }
        var roleRaw: CFTypeRef?; var titleRaw: CFTypeRef?; var descriptionRaw: CFTypeRef?; var valueRaw: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRaw)
        AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleRaw)
        AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &descriptionRaw)
        AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRaw)
        let role = (roleRaw as? String) ?? "AXElement"
        let label = [titleRaw as? String, descriptionRaw as? String, valueRaw as? String]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty }) ?? ""
        let usefulRoles = ["AXButton", "AXTextField", "AXTextArea", "AXCheckBox", "AXRadioButton", "AXPopUpButton", "AXLink", "AXMenuItem", "AXTab", "AXSlider"]
        if usefulRoles.contains(role) || !label.isEmpty {
            lines.append(label.isEmpty ? role : "\(role): \(String(label.prefix(180)))")
        }
        var childrenRaw: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRaw) == .success,
           let children = childrenRaw as? [AXUIElement] {
            for child in children where lines.count < limit { collectElements(child, depth: depth + 1, limit: limit, lines: &lines) }
        }
    }
}
