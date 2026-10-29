import AppKit
import Combine
import FoldBarCore

final class MenuBarController: NSObject, ObservableObject, NSMenuDelegate {
    @Published private(set) var state: BarState
    @Published private(set) var notice: String?
    @Published private(set) var shortcutAvailable = true
    @Published private(set) var layoutWarning: String?
    @Published private(set) var isRecoveringLayout = false
    @Published var settingsTab = 0
    var isManagingInventory = false
    let settings: Settings
    var showSettings: (() -> Void)?
    var settingsAreVisible: (() -> Bool)?

    // Creation order is right to left. autosaveName lets macOS keep the user's Cmd-drag placement.
    private(set) var control: NSStatusItem
    private(set) var divider: NSStatusItem
    private(set) var archive: NSStatusItem?
    private let shortcut = GlobalShortcut()
    private var timer: Timer?
    private var menuIsOpen = false
    private var observers: [NSObjectProtocol] = []
    private var visibilityObservations: [ObjectIdentifier: NSKeyValueObservation] = [:]
    private var shortcutWasEnabled: Bool?
    private var isShuttingDown = false
    private var namespace: String
    private let cleanupNamespace: String
    private let testing: Bool
    private(set) var hiddenProbe: NSStatusItem?
    private(set) var archiveProbe: NSStatusItem?

    init(settings: Settings, testing: Bool = false) {
        self.settings = settings
        self.testing = testing
        let initialNamespace = testing ? "selftest.\(UUID().uuidString)"
            : (settings.defaults.string(forKey: "itemPlacementNamespace") ?? "foldbar.v1")
        namespace = initialNamespace
        cleanupNamespace = initialNamespace
        state = BarState(archiveEnabled: settings.archiveEnabled)
        StatusItemPlacement.seed(name: "\(namespace).control", position: 0)
        StatusItemPlacement.seed(name: "\(namespace).divider", position: 1)
        control = NSStatusBar.system.statusItem(withLength: 30)
        divider = NSStatusBar.system.statusItem(withLength: BarGeometry.dividerWidth)
        super.init()
        configure(control, name: "control", symbol: "chevron.right", label: "FoldBar，点击打开图标配置，右键打开菜单")
        configure(divider, name: "divider", symbol: "1.circle", label: "① 普通收纳分隔线，左侧图标会被收起")
        if testing { hiddenProbe = makeProbe("H", name: "hidden-probe") }
        updateArchiveItem()
        if testing { archiveProbe = makeProbe("A", name: "archive-probe") }
        shortcut.onPress = { [weak self] in self?.toggle() }
        settings.onChange = { [weak self] in self?.preferencesChanged() }
        preferencesChanged()
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                                object: nil, queue: .main) { [weak self] _ in
            self?.applyAppearance()
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification,
                                                                          object: nil, queue: .main) { [weak self] _ in
            // Wake and display changes can invalidate the width; never reuse a cached display size.
            self?.applyAppearance()
        })
        applyAppearance()
    }

    private func configure(_ item: NSStatusItem, name: String, symbol: String, label: String) {
        item.autosaveName = "\(namespace).\(name)"
        item.isVisible = true
        item.behavior = []
        guard let button = item.button else { return }
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        button.image?.isTemplate = true
        button.toolTip = label
        button.setAccessibilityLabel(label)
        button.target = self
        button.action = #selector(clicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        visibilityObservations[ObjectIdentifier(item)] = item.observe(\.isVisible, options: [.new]) { [weak self, weak item] _, change in
            guard change.newValue == false else { return }
            DispatchQueue.main.async {
                guard let self, !self.isShuttingDown else { return }
                // Losing the only entry point would strand the user. Rearrangement is supported; removal is not.
                item?.isVisible = true
            }
        }
    }

    private func makeProbe(_ title: String, name: String) -> NSStatusItem {
        StatusItemPlacement.seed(name: "\(namespace).\(name)", position: title == "H" ? 2 : 4)
        let item = NSStatusBar.system.statusItem(withLength: 24)
        item.autosaveName = "\(namespace).\(name)"
        item.button?.title = title
        return item
    }

    private func updateArchiveItem() {
        if settings.archiveEnabled, archive == nil {
            StatusItemPlacement.seed(name: "\(namespace).archive", position: testing ? 3 : 180)
            let item = NSStatusBar.system.statusItem(withLength: BarGeometry.dividerWidth)
            configure(item, name: "archive", symbol: "2.circle", label: "② 深度收纳分隔线，仅整理时显示左侧图标")
            archive = item
        } else if !settings.archiveEnabled, let item = archive {
            item.length = BarGeometry.dividerWidth
            archive = nil
            // Invalidate this item's observer before deliberately removing it.
            visibilityObservations.removeValue(forKey: ObjectIdentifier(item))?.invalidate()
            StatusItemPlacement.remove(item)
        }
    }

    private func preferencesChanged() {
        let changedArchive = state.archiveEnabled != settings.archiveEnabled
        state.archiveEnabled = settings.archiveEnabled
        updateArchiveItem()
        if changedArchive { state.setMode(.organizing) }
        if shortcutWasEnabled != settings.shortcutEnabled {
            shortcutAvailable = shortcut.setEnabled(settings.shortcutEnabled && !testing)
            shortcutWasEnabled = settings.shortcutEnabled
        }
        applyAppearance()
        armAutoHide()
    }

    func setMode(_ mode: BarMode) {
        guard !isRecoveringLayout else { return }
        timer?.invalidate()
        notice = nil
        // Only measured item positions are trusted; never hide if the control has been dragged into a hidden group.
        if mode != .organizing && !arrangementIsValid {
            state.setMode(.organizing)
            applyAppearance()
            notice = "菜单栏控制项顺序异常，已暂停收起。请在「全局配置」中点击「恢复菜单栏位置」。"
            settingsTab = 1
            showSettings?()
            return
        }
        state.setMode(mode)
        applyAppearance()
        armAutoHide()
        if mode != .organizing {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in self?.verifyControlIsReachable() }
        }
    }

    func toggle() { setMode(state.mode == .collapsed ? .expanded : .collapsed) }

    var arrangementIsValid: Bool {
        BarGeometry.isOrdered(controlX: control.button?.window?.frame.maxX,
                              dividerX: divider.button?.window?.frame.maxX,
                              archiveX: archive?.button?.window?.frame.maxX,
                              archiveEnabled: state.archiveEnabled)
    }

    private func applyAppearance() {
        let width = BarGeometry.hidingWidth(screenWidths: NSScreen.screens.map { $0.frame.width })
        // This changes only our own spacers. Other applications keep ownership of their icons and menus.
        divider.length = state.mode == .collapsed ? width : BarGeometry.dividerWidth
        archive?.length = state.archiveIsHidden ? width : BarGeometry.dividerWidth
        divider.button?.image = state.mode == .collapsed ? nil : NSImage(systemSymbolName: "1.circle", accessibilityDescription: "① 普通收纳分隔线")
        archive?.button?.image = state.archiveIsHidden ? nil : NSImage(systemSymbolName: "2.circle", accessibilityDescription: "② 深度收纳分隔线")
        let symbol = state.mode == .collapsed ? "chevron.left" : "chevron.right"
        control.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "FoldBar \(state.mode.title)")
        control.button?.toolTip = "FoldBar · \(state.mode.title)\n点击打开图标配置 · ⌥ 点击全局配置 · 右键展开 / 收起"
        control.button?.setAccessibilityLabel("FoldBar \(state.mode.title)")
        refreshLayoutStatus()
    }

    func refreshLayoutStatus() {
        // Wait for WindowServer to finish repositioning the status windows before reading their frames.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self, !self.isShuttingDown else { return }
            guard self.state.mode == .organizing else { self.layoutWarning = nil; return }
            let missing = self.missingMarkers
            self.layoutWarning = missing.isEmpty ? nil : "\(missing.joined(separator: "、")) 被挤出可见区或被刘海遮挡，可用「恢复菜单栏位置」修复。"
        }
    }

    var missingMarkers: [String] {
        var items = [("箭头", control), ("① 普通收纳", divider)]
        if let archive { items.append(("② 深度收纳", archive)) }
        return items.filter { !StatusItemPlacement.isVisible($0.1) }.map { $0.0 }
    }

    /// Repair only our boundaries; the user deliberately requests this because their old positions are unusable.
    func recoverLayout() {
        guard !isRecoveringLayout else { return }
        isRecoveringLayout = true
        timer?.invalidate()
        state.setMode(.organizing)
        notice = nil
        divider.length = BarGeometry.dividerWidth
        archive?.length = BarGeometry.dividerWidth
        visibilityObservations.values.forEach { $0.invalidate() }
        visibilityObservations.removeAll()
        [control, divider, archive].compactMap { $0 }.forEach { StatusItemPlacement.remove($0, preservePosition: false) }
        archive = nil
        // Reusing an autosave name in the same run races AppKit's cached old position and deferred saves.
        // Fresh identities make the requested positions take effect; persist the new identities for later launches.
        namespace = "\(testing ? cleanupNamespace : "foldbar.v1").recovery.\(UUID().uuidString)"
        if !testing { settings.defaults.set(namespace, forKey: "itemPlacementNamespace") }
        // Keep the controls near the right edge. Leave some room between ② and ① for the regular group.
        for (name, position) in [("control", CGFloat(0)), ("divider", CGFloat(1)), ("archive", CGFloat(180))] {
            StatusItemPlacement.seed(name: "\(namespace).\(name)", position: position, overwrite: true)
        }
        control = NSStatusBar.system.statusItem(withLength: 30)
        divider = NSStatusBar.system.statusItem(withLength: BarGeometry.dividerWidth)
        configure(control, name: "control", symbol: "chevron.right", label: "FoldBar，点击打开图标配置，右键打开菜单")
        configure(divider, name: "divider", symbol: "1.circle", label: "① 普通收纳分隔线")
        updateArchiveItem()
        applyAppearance()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self else { return }
            self.isRecoveringLayout = false
            if self.missingMarkers.isEmpty && self.arrangementIsValid {
                self.notice = "菜单栏位置已恢复。分组边界已改变，请在「图标配置」中确认各项分组。"
            } else {
                self.notice = "右侧空间仍不足，可在「全局配置」中关闭深度收纳后重试。本次没有执行收起。"
            }
            self.refreshLayoutStatus()
        }
    }

    private func verifyControlIsReachable() {
        guard state.mode != .organizing else { return }
        let reachable = StatusItemPlacement.isVisible(control)
        let grew = state.mode != .collapsed || (divider.button?.window?.frame.width ?? 0) > BarGeometry.dividerWidth * 2
        guard reachable && grew else {
            state.setMode(.organizing)
            applyAppearance()
            notice = "当前菜单栏布局无法安全收起，已恢复所有分隔线。请检查箭头位置，以及是否有其他菜单栏管理 app 正在运行。"
            settingsTab = 1
            showSettings?()
            return
        }
        // Completing setup no longer depends on a separate layout page. Persist only after collapse is verified.
        if state.mode == .collapsed { settings.hasFinishedSetup = true }
    }

    func armAutoHide() {
        timer?.invalidate()
        guard settings.autoHide, state.mode == .expanded, !testing else { return }
        timer = Timer.scheduledTimer(withTimeInterval: settings.delay, repeats: false) { [weak self] _ in
            guard let self else { return }
            if self.state.mayAutoHide(enabled: self.settings.autoHide, interacting: self.isInteracting) {
                self.setMode(.collapsed)
            } else { self.armAutoHide() }
        }
    }

    private var isInteracting: Bool {
        if isManagingInventory || menuIsOpen || settingsAreVisible?() == true || NSEvent.pressedMouseButtons != 0 { return true }
        let point = NSEvent.mouseLocation
        let inMenuBar = NSScreen.screens.contains { screen in
            point.x >= screen.frame.minX && point.x <= screen.frame.maxX &&
            point.y >= screen.frame.maxY - max(NSStatusBar.system.thickness, screen.safeAreaInsets.top) && point.y <= screen.frame.maxY
        }
        if inMenuBar || NSEvent.modifierFlags.contains(.command) { return true }
        // Public window metadata is sufficient to defer while another app's popup menu is open; no pixels are captured.
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        return windows.contains { ($0[kCGWindowLayer as String] as? Int) == Int(NSWindow.Level.popUpMenu.rawValue) }
    }

    @objc private func clicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.modifierFlags.contains(.option) == true {
            settingsTab = 1
            showSettings?()
        } else if event?.type == .rightMouseUp || sender !== control.button {
            let menu = makeMenu()
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: 0), in: sender)
        } else { settingsTab = 0; showSettings?() }
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        let title = NSMenuItem(title: "FoldBar · \(state.mode.title)", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(.separator())
        addMenuItem("图标配置…", action: #selector(inventoryFromMenu), to: menu)
        addMenuItem(state.mode == .collapsed ? "展开收纳组" : "收起收纳组", action: #selector(toggleFromMenu), to: menu)
        addMenuItem("全局配置…", action: #selector(settingsFromMenu), to: menu)
        menu.addItem(.separator())
        addMenuItem("退出 FoldBar（恢复显示）", action: #selector(quit), to: menu)
        return menu
    }

    private func addMenuItem(_ title: String, action: Selector, to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
    }

    func menuWillOpen(_ menu: NSMenu) { menuIsOpen = true; timer?.invalidate() }
    func menuDidClose(_ menu: NSMenu) { menuIsOpen = false; armAutoHide() }
    @objc private func toggleFromMenu() { toggle() }
    @objc private func inventoryFromMenu() { settingsTab = 0; showSettings?() }
    @objc private func settingsFromMenu() { settingsTab = 1; showSettings?() }
    @objc private func quit() { NSApp.terminate(nil) }

    func shutdown() {
        guard !isShuttingDown else { return }
        isShuttingDown = true
        timer?.invalidate()
        shortcut.setEnabled(false)
        visibilityObservations.values.forEach { $0.invalidate() }
        // Restore first so shutdown never leaves a large spacer in an intermediate layout.
        divider.length = BarGeometry.dividerWidth
        archive?.length = BarGeometry.dividerWidth
        [control, divider, archive, hiddenProbe, archiveProbe].compactMap { $0 }.forEach { StatusItemPlacement.remove($0) }
        observers.forEach {
            NotificationCenter.default.removeObserver($0)
            NSWorkspace.shared.notificationCenter.removeObserver($0)
        }
        if testing {
            for key in UserDefaults.standard.dictionaryRepresentation().keys where key.contains(cleanupNamespace) {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
    }
}
