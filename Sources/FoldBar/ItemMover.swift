import AppKit
import ApplicationServices
import FoldBarCore

enum ItemMoveError: LocalizedError {
    case permission, unavailable, fixed, busy, unsupported
    var errorDescription: String? {
        switch self {
        case .permission: return "请先在系统设置中允许 FoldBar 的辅助功能权限，再重试。"
        case .unavailable: return "这个图标或目标分隔线已经变化，请刷新列表后重试。"
        case .fixed: return "这个系统项目不支持移动。"
        case .busy: return "请先松开鼠标和修饰键，再点击移动。"
        case .unsupported: return "macOS 未完成这次移动，位置检查未通过。图标仍保留在列表中，可刷新后重试。"
        }
    }
}

@MainActor
final class ItemMover {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func requestPermission() {
        AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Move one known status window to an anchor, including when its original coordinates are offscreen.
    /// No other app preferences are rewritten. Only confirmed WindowServer position changes count as success.
    func move(_ item: InventoryItem, to group: ItemGroup, controller: MenuBarController) async throws {
        guard Self.isTrusted else { throw ItemMoveError.permission }
        guard !controller.isRecoveringLayout else { throw ItemMoveError.unavailable }
        guard item.isMovable else { throw ItemMoveError.fixed }
        guard NSEvent.pressedMouseButtons == 0, NSEvent.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty else {
            throw ItemMoveError.busy
        }
        guard ItemInventory.current(item) != nil else { throw ItemMoveError.unavailable }
        controller.setMode(.organizing)
        try await Task.sleep(nanoseconds: 300_000_000)
        guard let current = ItemInventory.current(item),
              let control = ItemInventory.frame(of: controller.control),
              let divider = ItemInventory.frame(of: controller.divider) else { throw ItemMoveError.unavailable }
        let archive = ItemInventory.frame(of: controller.archive)
        if InventoryRules.hasReached(group, item: current.frame, control: control, divider: divider, archive: archive),
           group != .visible || ItemInventory.isActuallyVisible(current) { return }
        let anchor: NSStatusItem
        switch group {
        case .visible: anchor = controller.control
        case .hidden: anchor = controller.divider
        case .archive:
            guard let item = controller.archive else { throw ItemMoveError.unavailable }
            anchor = item
        }
        guard StatusItemPlacement.isVisible(anchor), let target = ItemInventory.frame(of: anchor),
              let targetID = anchor.button?.window?.windowNumber else { throw ItemMoveError.unavailable }
        let end = CGPoint(x: group == .visible ? target.maxX + 1 : target.minX - 1, y: target.midY)
        let originalPointer = CGEvent(source: nil)?.location
        defer {
            // Restoring the cursor does not replay a click or change keyboard state.
            if let originalPointer { CGWarpMouseCursorPosition(originalPointer) }
        }
        try await drag(item: current, destination: end, anchorID: CGWindowID(targetID))
        try await Task.sleep(nanoseconds: 350_000_000)
        guard let moved = ItemInventory.current(item), let newControl = ItemInventory.frame(of: controller.control),
              let newDivider = ItemInventory.frame(of: controller.divider),
              InventoryRules.hasReached(group, item: moved.frame, control: newControl, divider: newDivider,
                                        archive: ItemInventory.frame(of: controller.archive)),
              group != .visible || ItemInventory.isActuallyVisible(moved) else { throw ItemMoveError.unsupported }
    }

    private func event(_ type: CGEventType, source: CGEventSource, item: InventoryItem, at point: CGPoint, windowID: CGWindowID, command: Bool) -> CGEvent? {
        guard let event = CGEvent(mouseEventSource: source, mouseType: type,
                                  mouseCursorPosition: point, mouseButton: .left) else { return nil }
        event.flags = command ? .maskCommand : []
        event.setIntegerValueField(.eventTargetUnixProcessID, value: Int64(item.pid))
        event.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: Int64(windowID))
        event.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: Int64(windowID))
        // AppKit status-item dragging requires the NSEvent window number even when the cursor cannot hit the item.
        // 0x33 is not a documented Quartz field; keep this compatibility detail isolated and verify every move.
        event.setIntegerValueField(CGEventField(rawValue: 0x33)!, value: Int64(windowID))
        event.setIntegerValueField(.mouseEventClickState, value: 1)
        return event
    }

    private func drag(item: InventoryItem, destination: CGPoint, anchorID: CGWindowID) async throws {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { throw ItemMoveError.unsupported }
        source.localEventsSuppressionInterval = 0
        let mask: CGEventFilterMask = [.permitLocalMouseEvents, .permitLocalKeyboardEvents, .permitSystemDefinedEvents]
        source.setLocalEventsFilterDuringSuppressionState(mask, state: .eventSuppressionStateRemoteMouseDrag)
        source.setLocalEventsFilterDuringSuppressionState(mask, state: .eventSuppressionStateSuppressionInterval)
        let start = CGPoint(x: 20_000, y: 20_000)
        guard let down = event(.leftMouseDown, source: source, item: item, at: start, windowID: item.id, command: true),
              let up = event(.leftMouseUp, source: source, item: item, at: destination, windowID: anchorID, command: false) else {
            throw ItemMoveError.unsupported
        }
        var released = false
        // Always release the simulated drag, including cancellation or failure of the session acknowledgement.
        defer { if !released { up.post(tap: .cgSessionEventTap); up.postToPid(item.pid) } }
        try await StatusEventRelay(event: down, pid: item.pid).deliver()
        try await Task.sleep(nanoseconds: 180_000_000)
        try await StatusEventRelay(event: up, pid: item.pid).deliver()
        released = true
    }
}
