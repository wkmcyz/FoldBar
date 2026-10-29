import AppKit
import Combine
import ServiceManagement

final class Settings: ObservableObject {
    let defaults: UserDefaults
    var onChange: (() -> Void)?

    @Published var autoHide: Bool { didSet { save(autoHide, "autoHide") } }
    @Published var delay: Double { didSet { save(delay, "delay") } }
    @Published var archiveEnabled: Bool { didSet { save(archiveEnabled, "archiveEnabled") } }
    @Published var shortcutEnabled: Bool { didSet { save(shortcutEnabled, "shortcutEnabled") } }
    @Published var startCollapsed: Bool { didSet { save(startCollapsed, "startCollapsed") } }
    @Published private(set) var loginEnabled = false
    @Published private(set) var loginMessage: String?

    var hasFinishedSetup: Bool {
        get { defaults.bool(forKey: "hasFinishedSetup") }
        set { defaults.set(newValue, forKey: "hasFinishedSetup") }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: ["autoHide": true, "delay": 15.0, "shortcutEnabled": true,
                                      "archiveEnabled": false, "startCollapsed": true])
        autoHide = defaults.bool(forKey: "autoHide")
        delay = min(60, max(5, defaults.double(forKey: "delay")))
        archiveEnabled = defaults.bool(forKey: "archiveEnabled")
        shortcutEnabled = defaults.bool(forKey: "shortcutEnabled")
        startCollapsed = defaults.bool(forKey: "startCollapsed")
        refreshLoginStatus()
    }

    private func save(_ value: Any, _ key: String) {
        defaults.set(value, forKey: key)
        onChange?()
    }

    func refreshLoginStatus() {
        let status = SMAppService.mainApp.status
        loginEnabled = status == .enabled || status == .requiresApproval
        loginMessage = status == .requiresApproval ? "请在系统设置 → 通用 → 登录项中允许 FoldBar。" : nil
    }

    func setLoginEnabled(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            refreshLoginStatus()
        } catch {
            refreshLoginStatus()
            loginMessage = "设置失败：\(error.localizedDescription) 建议先将 app 移到「应用程序」。"
        }
    }
}
