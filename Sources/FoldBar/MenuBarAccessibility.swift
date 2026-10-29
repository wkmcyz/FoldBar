import AppKit
import ApplicationServices
import FoldBarCore

struct MenuExtraMetadata {
    let frame: CGRect?
    let identifier: String
    let title: String
    let description: String
    let role: String

    var label: String {
        let text = description.isEmpty ? title : description
        return text.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

struct MenuExtrasSnapshot {
    let readable: Bool
    let entries: [MenuExtraMetadata]
}

/// Read only the status-menu subtree, never application documents or opened menu contents.
enum MenuBarAccessibility {
    private enum ReadFailure: Error { case unavailable }

    static func snapshots(for pids: Set<pid_t>) async -> [pid_t: MenuExtrasSnapshot] {
        await Task.detached(priority: .utility) {
            guard AXIsProcessTrusted() else { return [:] }
            return Dictionary(uniqueKeysWithValues: pids.map { ($0, read(pid: $0)) })
        }.value
    }

    static func matches(items: [InventoryItem], snapshots: [pid_t: MenuExtrasSnapshot]) -> [InventoryIdentity: MenuExtraMetadata] {
        var result: [InventoryIdentity: MenuExtraMetadata] = [:]
        for (pid, snapshot) in snapshots where snapshot.readable {
            var remaining = items.filter { $0.pid == pid }
            for entry in snapshot.entries {
                let candidates = remaining.filter { item in
                    entry.frame.map { InventoryRules.matchesMenuExtra(window: item.frame, extra: $0) }
                        ?? (remaining.count == 1 && snapshot.entries.count == 1)
                }
                let best = candidates.min { a, b in
                    // Prefer a live window over a stale copy at the same location; one AX item maps to at most one window.
                    if a.isOnScreen != b.isOnScreen { return a.isOnScreen }
                    let x = entry.frame?.midX ?? a.frame.midX
                    if abs(a.frame.midX - x) != abs(b.frame.midX - x) { return abs(a.frame.midX - x) < abs(b.frame.midX - x) }
                    return a.id > b.id
                }
                if let best {
                    result[best.identity] = entry
                    remaining.removeAll { $0.identity == best.identity }
                }
            }
        }
        return result
    }

    private static func read(pid: pid_t) -> MenuExtrasSnapshot {
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, 0.15)
        do {
            let elements: [AXUIElement]
            if let value = try attribute(application, kAXExtrasMenuBarAttribute), CFGetTypeID(value) == AXUIElementGetTypeID() {
                let bar = value as! AXUIElement
                AXUIElementSetMessagingTimeout(bar, 0.15)
                guard let children = try attribute(bar, kAXChildrenAttribute) as? [AXUIElement] else {
                    return MenuExtrasSnapshot(readable: false, entries: [])
                }
                elements = children
            } else {
                // Some older apps expose menu extras directly. Do not inspect the ordinary File/Edit menu bar.
                guard let children = try attribute(application, kAXChildrenAttribute) as? [AXUIElement] else {
                    return MenuExtrasSnapshot(readable: false, entries: [])
                }
                elements = try children.filter {
                    AXUIElementSetMessagingTimeout($0, 0.15)
                    return try string($0, kAXRoleAttribute) == "AXMenuExtra"
                }
                // A responding app with no menu extras has no enabled status item. Do not keep its cached windows.
            }
            let entries = try elements.compactMap { element -> MenuExtraMetadata? in
                AXUIElementSetMessagingTimeout(element, 0.15)
                let role = try string(element, kAXRoleAttribute)
                guard ["AXMenuBarItem", "AXMenuExtra", "AXButton"].contains(role) else { return nil }
                return MenuExtraMetadata(frame: try frame(element), identifier: try string(element, kAXIdentifierAttribute),
                                         title: try string(element, kAXTitleAttribute), description: try string(element, kAXDescriptionAttribute), role: role)
            }
            return MenuExtrasSnapshot(readable: true, entries: entries)
        } catch {
            // A hung owner must not freeze the configuration window or be treated as a confirmed removal.
            return MenuExtrasSnapshot(readable: false, entries: [])
        }
    }

    private static func attribute(_ element: AXUIElement, _ key: String) throws -> CFTypeRef? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, key as CFString, &value)
        if error == .cannotComplete || error == .invalidUIElement { throw ReadFailure.unavailable }
        return error == .success ? value : nil
    }

    private static func string(_ element: AXUIElement, _ key: String) throws -> String {
        try attribute(element, key) as? String ?? ""
    }

    private static func frame(_ element: AXUIElement) throws -> CGRect? {
        guard let position = try attribute(element, kAXPositionAttribute), CFGetTypeID(position) == AXValueGetTypeID(),
              let size = try attribute(element, kAXSizeAttribute), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        var dimensions = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &point), AXValueGetValue(size as! AXValue, .cgSize, &dimensions) else { return nil }
        return CGRect(origin: point, size: dimensions)
    }
}
