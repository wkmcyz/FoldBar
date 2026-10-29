import AppKit
import FoldBarCore

enum StatusItemPlacement {
    static func key(for name: String) -> String { "NSStatusItem Preferred Position \(name)" }

    /// AppKit has no public position setter. Seed its own autosave preference before creating an item.
    /// This undocumented preference is restricted to FoldBar's items and always followed by geometry verification.
    /// Never rewrite another application's position or the global menu-bar spacing settings.
    static func seed(name: String, position: CGFloat, overwrite: Bool = false) {
        let key = key(for: name)
        if overwrite || UserDefaults.standard.object(forKey: key) == nil {
            UserDefaults.standard.set(position, forKey: key)
        }
    }

    static func remove(_ item: NSStatusItem, preservePosition: Bool = true) {
        let key = item.autosaveName.map { self.key(for: $0) }
        let saved = key.flatMap { UserDefaults.standard.object(forKey: $0) }
        NSStatusBar.system.removeStatusItem(item)
        // AppKit clears this preference on removal. Keep the user's Cmd-drag placement across a normal quit.
        if preservePosition, let key, let saved { UserDefaults.standard.set(saved, forKey: key) }
    }

    static func isVisible(_ item: NSStatusItem?) -> Bool {
        guard let item, item.isVisible, let window = item.button?.window else { return false }
        return isVisible(frame: window.frame)
    }

    static func isVisible(frame: CGRect) -> Bool {
        NSScreen.screens.contains { screen in
            let areas: [CGRect]
            if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
                areas = [left, right]
            } else {
                areas = [CGRect(x: screen.frame.minX, y: screen.frame.maxY - NSStatusBar.system.thickness - 6,
                                width: screen.frame.width, height: NSStatusBar.system.thickness + 6)]
            }
            return BarGeometry.isVisible(frame: frame, screen: screen.frame, menuBarAreas: areas)
        }
    }
}
