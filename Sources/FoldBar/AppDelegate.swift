import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var controller: MenuBarController?
    private var settings: Settings?
    private var preferencesWindow: NSWindow?
    private var startupTimer: Timer?
    private var selfTest: MenuBarSelfTest?
    private var inventory: InventoryModel?
    private var inventoryTest: InventorySelfTest?
    private var fixture: InventoryFixture?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        installApplicationMenu()
        if CommandLine.arguments.contains("--inventory-diagnostics") {
            Task {
                let items = ItemInventory.scan()
                let snapshots = await MenuBarAccessibility.snapshots(for: Set(items.map(\.pid)))
                let rows: [[String: Any]] = items.map { item in
                    let snapshot = snapshots[item.pid]
                    return ["app": item.application, "bundle": item.bundleID ?? "", "pid": item.pid, "id": item.id,
                            "windowTitle": item.windowTitle, "frame": NSStringFromRect(item.frame), "onScreen": item.isOnScreen,
                            "axReadable": snapshot?.readable ?? false,
                            "extras": snapshot?.entries.map { ["id": $0.identifier, "title": $0.title, "description": $0.description,
                                                               "role": $0.role, "frame": $0.frame.map(NSStringFromRect) ?? ""] } ?? []]
                }
                if let data = try? JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys]),
                   let text = String(data: data, encoding: .utf8) { print(text) }
                NSApp.terminate(nil)
            }
            return
        }
        if let index = CommandLine.arguments.firstIndex(of: "--inventory-fixture"), CommandLine.arguments.indices.contains(index + 1) {
            fixture = InventoryFixture(name: CommandLine.arguments[index + 1])
            return
        }
        if let index = CommandLine.arguments.firstIndex(of: "--inventory-self-test"), CommandLine.arguments.indices.contains(index + 1) {
            let suite = "com.wkm.foldbar.inventory-test.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suite)!
            defaults.set(true, forKey: "archiveEnabled")
            let settings = Settings(defaults: defaults)
            self.settings = settings
            let controller = MenuBarController(settings: settings, testing: true)
            self.controller = controller
            let test = InventorySelfTest(controller: controller, output: CommandLine.arguments[index + 1])
            inventoryTest = test
            test.start { defaults.removePersistentDomain(forName: suite); NSApp.terminate(nil) }
            return
        }
        if let index = CommandLine.arguments.firstIndex(of: "--self-test"), CommandLine.arguments.indices.contains(index + 1) {
            let suite = "com.wkm.foldbar.selftest.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suite)!
            defaults.set(true, forKey: "archiveEnabled")
            let settings = Settings(defaults: defaults)
            self.settings = settings
            let controller = MenuBarController(settings: settings, testing: true)
            self.controller = controller
            let test = MenuBarSelfTest(controller: controller, output: CommandLine.arguments[index + 1])
            selfTest = test
            test.start { defaults.removePersistentDomain(forName: suite); NSApp.terminate(nil) }
            return
        }
        let settings = Settings()
        self.settings = settings
        let controller = MenuBarController(settings: settings)
        self.controller = controller
        inventory = InventoryModel(controller: controller)
        controller.showSettings = { [weak self] in self?.openPreferences() }
        controller.settingsAreVisible = { [weak self] in self?.preferencesWindow?.isVisible ?? false }
        if !settings.hasFinishedSetup {
            openPreferences()
        } else if settings.startCollapsed {
            // Give other login items time to register before applying a previously configured layout.
            startupTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: false) { [weak self] _ in
                guard let self, self.preferencesWindow?.isVisible != true, self.controller?.state.mode == .organizing else { return }
                self.controller?.setMode(.collapsed)
            }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { controller.setMode(.expanded) }
        }
    }

    @objc func openPreferences() {
        startupTimer?.invalidate()
        guard let controller, let settings, let inventory else { return }
        settings.refreshLoginStatus()
        controller.refreshLayoutStatus()
        if preferencesWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 770, height: 650),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "FoldBar · 折叠栏"
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.minSize = NSSize(width: 760, height: 650)
            window.setFrameAutosaveName("FoldBarPreferences")
            window.contentView = NSHostingView(rootView: PreferencesView(controller: controller, settings: settings, inventory: inventory))
            window.delegate = self
            window.center()
            preferencesWindow = window
        }
        preferencesWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openGlobalSettings() {
        controller?.settingsTab = 1
        openPreferences()
    }

    func windowWillClose(_ notification: Notification) { controller?.armAutoHide() }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openPreferences()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        startupTimer?.invalidate()
        controller?.shutdown()
    }

    private func installApplicationMenu() {
        let root = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        let settingsItem = NSMenuItem(title: "全局配置…", action: #selector(openGlobalSettings), keyEquivalent: ",")
        settingsItem.target = self
        appMenu.addItem(settingsItem)
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "退出 FoldBar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appItem.submenu = appMenu
        root.addItem(appItem)
        NSApp.mainMenu = root
    }
}
