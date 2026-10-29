import Foundation
import CoreGraphics

public enum ItemGroup: String, CaseIterable, Identifiable {
    case visible, hidden, archive
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .visible: return "常用常驻"
        case .hidden: return "普通收纳"
        case .archive: return "深度收纳"
        }
    }
}

public enum InventoryRules {
    public enum MembershipEvidence { case active, inactive, unavailable }

    /// WindowServer retains ordered-out windows. Their shape is not evidence of an enabled menu item.
    /// When an owner is temporarily unresponsive, retain only an already-confirmed item displaced by our spacers.
    public static func isEnabledMenuItem(onScreen: Bool, evidence: MembershipEvidence,
                                         previouslyActive: Bool, displacedByFoldBar: Bool) -> Bool {
        if evidence == .active || onScreen { return true }
        if evidence == .inactive { return false }
        return previouslyActive && displacedByFoldBar
    }

    public static func matchesMenuExtra(window: CGRect, extra: CGRect) -> Bool {
        abs(window.midX - extra.midX) <= 8 && abs(window.midY - extra.midY) <= 12 &&
            extra.width > 0 && extra.height > 0 && extra.width <= window.width + 2 && extra.height <= window.height + 8
    }

    /// Include offscreen status windows, but exclude popovers, overlays and stale copies with another menu-bar height.
    public static func isStatusItem(frame: CGRect, layer: Int, statusLayer: Int, menuBands: [CGRect]) -> Bool {
        guard layer == statusLayer, frame.width >= 8, frame.width <= 600, frame.height >= 16, frame.height <= 70 else { return false }
        return menuBands.contains { abs(frame.minY - $0.minY) <= 3 && abs(frame.height - $0.height) <= 8 }
    }

    public static func group(of frame: CGRect, divider: CGRect, archive: CGRect?) -> ItemGroup {
        if let archive, frame.maxX <= archive.minX + 2 { return .archive }
        if frame.maxX <= divider.minX + 2 { return .hidden }
        return .visible
    }

    public static func hasReached(_ group: ItemGroup, item: CGRect, control: CGRect, divider: CGRect, archive: CGRect?) -> Bool {
        switch group {
        case .visible: return item.minX >= control.maxX - 2
        case .hidden:
            return item.maxX <= divider.minX + 2 && (archive == nil || item.minX >= archive!.maxX - 2)
        case .archive: return archive.map { item.maxX <= $0.minX + 2 } ?? false
        }
    }
}
