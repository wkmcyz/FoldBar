import Foundation
import CoreGraphics

public enum BarMode: String, Codable {
    case collapsed, expanded, organizing

    public var title: String {
        switch self {
        case .collapsed: return "已收起"
        case .expanded: return "已展开"
        case .organizing: return "正在整理"
        }
    }
}

/// Organizing is an explicit mode: timers never hide items while the user drags them.
public struct BarState: Equatable {
    public private(set) var mode: BarMode = .organizing
    public var archiveEnabled: Bool

    public init(archiveEnabled: Bool = false) {
        self.archiveEnabled = archiveEnabled
    }

    public mutating func setMode(_ mode: BarMode) { self.mode = mode }

    public mutating func toggle() {
        mode = mode == .collapsed ? .expanded : .collapsed
    }

    public var archiveIsHidden: Bool { archiveEnabled && mode != .organizing }

    public func mayAutoHide(enabled: Bool, interacting: Bool) -> Bool {
        enabled && mode == .expanded && !interacting
    }
}

public enum BarGeometry {
    public static let dividerWidth: CGFloat = 22

    public static func hidingWidth(screenWidths: [CGFloat]) -> CGFloat {
        let widest = screenWidths.filter { $0.isFinite && $0 > 0 }.max() ?? 1920
        return min(10_000, max(500, widest * 2))
    }

    /// A status window can be inside the display yet completely hidden by the camera housing.
    /// The window includes a small vertical shadow, so only its center's Y and full horizontal extent are checked.
    public static func isVisible(frame: CGRect, screen: CGRect, menuBarAreas: [CGRect]) -> Bool {
        guard screen.contains(CGPoint(x: frame.midX, y: frame.midY)) else { return false }
        return menuBarAreas.contains { area in
            frame.minX >= area.minX && frame.maxX <= area.maxX && frame.midY >= area.minY && frame.midY <= area.maxY
        }
    }

    /// The button must remain to the right of both dividers, or hiding would hide the control itself.
    public static func isOrdered(controlX: CGFloat?, dividerX: CGFloat?, archiveX: CGFloat?, archiveEnabled: Bool) -> Bool {
        guard let controlX, let dividerX, dividerX < controlX else { return false }
        if archiveEnabled {
            guard let archiveX, archiveX < dividerX else { return false }
        }
        return true
    }
}
