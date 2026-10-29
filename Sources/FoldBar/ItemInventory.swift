import AppKit
import ApplicationServices
import FoldBarCore

struct InventoryIdentity: Hashable {
    let pid: pid_t
    let windowID: CGWindowID
}

struct InventoryItem: Identifiable {
    let id: CGWindowID
    let pid: pid_t
    let application: String
    let bundleID: String?
    let windowTitle: String
    let frame: CGRect // Quartz global coordinates, origin at primary display's top-left.
    let isOnScreen: Bool
    var group: ItemGroup = .visible
    var accessibilityIdentifier = ""
    var accessibilityLabel = ""
    var accessibilityFrame: CGRect?

    var identity: InventoryIdentity { InventoryIdentity(pid: pid, windowID: id) }

    private var systemKey: String {
        let key = accessibilityIdentifier.isEmpty ? windowTitle : String(accessibilityIdentifier.split(separator: ".").last ?? "")
        return key.lowercased().replacingOccurrences(of: "-", with: "")
    }

    var isUnidentifiedSystemItem: Bool {
        bundleID == "com.apple.controlcenter" && systemKey.isEmpty && accessibilityLabel.isEmpty
    }

    var title: String {
        if bundleID == "com.apple.controlcenter" {
            return ["clock": "时钟", "bentobox": "控制中心", "controlcenter": "控制中心", "wifi": "Wi-Fi", "battery": "电池",
                    "hearing": "听觉（Hearing）", "userswitcher": "用户切换", "user": "用户切换", "focusmodes": "专注模式", "focus": "专注模式",
                    "nowplaying": "正在播放", "audiovideomodule": "音视频状态", "audiovideo": "音视频状态", "accessibilityshortcuts": "辅助功能快捷键",
                    "accessibility": "辅助功能快捷键", "bluetooth": "蓝牙", "sound": "声音", "display": "显示器",
                    "screenmirroring": "屏幕镜像", "airdrop": "隔空投送", "musicrecognition": "音乐识别"][systemKey]
                ?? (!accessibilityLabel.isEmpty ? accessibilityLabel : "控制中心 · \(windowTitle.isEmpty ? systemKey : windowTitle)")
        }
        return application
    }

    var isMovable: Bool {
        // System-owned fixed entries cannot be Cmd-dragged. A failed move of any other entry is reported, never assumed successful.
        !(bundleID == "com.apple.controlcenter" && (["clock", "bentobox", "controlcenter", "audiovideomodule", "audiovideo"].contains(systemKey) || isUnidentifiedSystemItem))
            && bundleID != "com.apple.Spotlight"
    }
}

enum ItemInventory {
    static var primaryTop: CGFloat { NSScreen.screens.first?.frame.maxY ?? 0 }

    static func quartzFrame(_ frame: CGRect) -> CGRect {
        CGRect(x: frame.minX, y: primaryTop - frame.maxY, width: frame.width, height: frame.height)
    }

    static func appKitFrame(_ frame: CGRect) -> CGRect {
        CGRect(x: frame.minX, y: primaryTop - frame.maxY, width: frame.width, height: frame.height)
    }

    static func frame(of item: NSStatusItem?) -> CGRect? {
        item?.button?.window.map { quartzFrame($0.frame) }
    }

    static func windows() -> [[String: Any]] {
        CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
    }

    static func scan(excludingPID: pid_t? = ProcessInfo.processInfo.processIdentifier) -> [InventoryItem] {
        let windows = windows()
        let statusLayer = Int(CGWindowLevelForKey(.statusWindow))
        let bands = NSScreen.screens.map { screen -> CGRect in
            let expected = quartzFrame(CGRect(x: screen.frame.minX, y: screen.frame.maxY - 43, width: screen.frame.width, height: 43))
            // WindowServer's menubar window includes the shadow; use its actual height when available.
            return windows.compactMap { info -> CGRect? in
                guard (info[kCGWindowLayer as String] as? Int) == Int(CGWindowLevelForKey(.mainMenuWindow)),
                      let raw = info[kCGWindowBounds as String] as? NSDictionary,
                      let rect = CGRect(dictionaryRepresentation: raw), abs(rect.width - screen.frame.width) < 2,
                      abs(rect.minY - expected.minY) < 2, rect.height >= 20, rect.height <= 70 else { return nil }
                return rect
            }.first ?? CGRect(x: expected.minX, y: expected.minY, width: expected.width,
                              height: max(NSStatusBar.system.thickness, screen.safeAreaInsets.top + 5))
        }
        return windows.compactMap { info in
            guard let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid != excludingPID,
                  let id = info[kCGWindowNumber as String] as? CGWindowID,
                  let raw = info[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: raw),
                  InventoryRules.isStatusItem(frame: frame, layer: info[kCGWindowLayer as String] as? Int ?? -1,
                                              statusLayer: statusLayer, menuBands: bands) else { return nil }
            let app = NSRunningApplication(processIdentifier: pid)
            return InventoryItem(id: id, pid: pid, application: app?.localizedName ?? info[kCGWindowOwnerName as String] as? String ?? "未知应用",
                                 bundleID: app?.bundleIdentifier, windowTitle: info[kCGWindowName as String] as? String ?? "",
                                 frame: frame, isOnScreen: info[kCGWindowIsOnscreen as String] as? Bool ?? false)
        }.sorted { $0.frame.minX > $1.frame.minX }
    }

    static func current(_ item: InventoryItem) -> InventoryItem? {
        // Window IDs alone can be reused after an app exits. Validate the owner as well before every action.
        scan(excludingPID: nil).first { $0.id == item.id && $0.pid == item.pid }
    }

    static func isActuallyVisible(_ item: InventoryItem) -> Bool {
        // AX reports the button content, excluding WindowServer shadows that can extend beyond the display edge.
        item.isOnScreen && StatusItemPlacement.isVisible(frame: appKitFrame(item.accessibilityFrame ?? item.frame))
    }
}
