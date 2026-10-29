import AppKit
import FoldBarCore

final class InventoryFixture {
    private let item: NSStatusItem
    init(name: String) {
        StatusItemPlacement.seed(name: name, position: 10_000, overwrite: true)
        item = NSStatusBar.system.statusItem(withLength: 36)
        item.autosaveName = name
        item.button?.title = "FBT"
        item.button?.setAccessibilityLabel("FoldBar integration test fixture")
        item.isVisible = true
        if CommandLine.arguments.contains("--fixture-control-stdin") {
            FileHandle.standardInput.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard !data.isEmpty else { handle.readabilityHandler = nil; return }
                let commands = String(decoding: data, as: UTF8.self).split(separator: "\n")
                DispatchQueue.main.async {
                    for command in commands {
                        if command == "hide" { self?.item.isVisible = false }
                        if command == "show" { self?.item.isVisible = true }
                    }
                }
            }
        }
    }
}

@MainActor
final class InventorySelfTest {
    private let controller: MenuBarController
    private let output: String
    private var checks: [[String: Any]] = []
    private var snapshots: [[String: Any]] = []

    init(controller: MenuBarController, output: String) { self.controller = controller; self.output = output }

    func start(completion: @escaping () -> Void) {
        Task {
            let fixtureName = "foldbar.fixture.\(UUID().uuidString)"
            let child = Process()
            let input = Pipe()
            child.executableURL = Bundle.main.executableURL
            child.arguments = ["--inventory-fixture", fixtureName, "--fixture-control-stdin"]
            child.standardInput = input
            child.standardOutput = FileHandle.nullDevice
            child.standardError = FileHandle.nullDevice
            defer {
                if child.isRunning { child.terminate(); child.waitUntilExit() }
                UserDefaults.standard.removeObject(forKey: StatusItemPlacement.key(for: fixtureName))
                finish()
                completion()
            }
            do {
                try child.run()
                try await Task.sleep(nanoseconds: 800_000_000)
                controller.setMode(.collapsed)
                try await Task.sleep(nanoseconds: 400_000_000)
                let inventory = ItemInventory.scan()
                check("scans nonempty real inventory", !inventory.isEmpty)
                guard var fixture = inventory.first(where: { $0.pid == child.processIdentifier }) else {
                    check("finds fixture owned by a different process", false)
                    return
                }
                check("finds fixture owned by a different process", true)
                check("finds fixture while physically hidden", !ItemInventory.isActuallyVisible(fixture))
                snapshot("before", fixture)
                check("test process has accessibility permission", ItemMover.isTrusted)
                guard ItemMover.isTrusted else { return }
                let model = InventoryModel(controller: controller)
                controller.settingsAreVisible = { true }
                model.startMonitoring()
                await waitForRefresh(model)
                // Let the one-time startup capture finish before exercising recurring refreshes.
                try await Task.sleep(nanoseconds: 700_000_000)
                await waitForRefresh(model)
                check("enabled offscreen fixture remains in configured list", model.items.contains { $0.pid == child.processIdentifier })
                try input.fileHandleForWriting.write(contentsOf: Data("hide\n".utf8))
                await waitUntil { !model.items.contains { $0.pid == child.processIdentifier } }
                check("disabled fixture is removed while its owner is alive", child.isRunning && !model.items.contains { $0.pid == child.processIdentifier })
                try input.fileHandleForWriting.write(contentsOf: Data("show\n".utf8))
                await waitUntil { model.items.contains { $0.pid == child.processIdentifier } }
                model.stopMonitoring()
                guard let reenabled = model.items.first(where: { $0.pid == child.processIdentifier }) else {
                    check("re-enabled fixture reappears", false)
                    return
                }
                check("re-enabled fixture reappears", true)
                fixture = reenabled
                let mover = ItemMover()
                for group in [ItemGroup.visible, .hidden, .archive, .visible] {
                    do {
                        try await mover.move(fixture, to: group, controller: controller)
                        check("moves hidden fixture to \(group.rawValue)", true)
                        if let current = ItemInventory.current(fixture) { snapshot(group.rawValue, current) }
                    } catch {
                        check("moves hidden fixture to \(group.rawValue): \(error.localizedDescription)", false)
                        if let current = ItemInventory.current(fixture) { snapshot("failed-\(group.rawValue)", current) }
                        break
                    }
                }
            } catch { check("fixture lifecycle: \(error.localizedDescription)", false) }
        }
    }

    private func waitForRefresh(_ model: InventoryModel) async {
        let deadline = Date().addingTimeInterval(5)
        while model.isRefreshing && Date() < deadline { try? await Task.sleep(nanoseconds: 40_000_000) }
        check("inventory refresh finishes within its budget", !model.isRefreshing)
    }

    private func waitUntil(_ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(5)
        while !condition() && Date() < deadline { try? await Task.sleep(nanoseconds: 50_000_000) }
        check("automatic refresh reflects the fixture change", condition())
    }

    private func check(_ name: String, _ passed: Bool) { checks.append(["name": name, "passed": passed]) }
    private func snapshot(_ mode: String, _ item: InventoryItem) {
        snapshots.append(["step": mode, "item": NSStringFromRect(item.frame), "visible": ItemInventory.isActuallyVisible(item),
                          "control": ItemInventory.frame(of: controller.control).map(NSStringFromRect) ?? "missing",
                          "divider": ItemInventory.frame(of: controller.divider).map(NSStringFromRect) ?? "missing",
                          "archive": ItemInventory.frame(of: controller.archive).map(NSStringFromRect) ?? "missing"])
    }
    private func finish() {
        let passed = checks.allSatisfy { $0["passed"] as? Bool == true }
        let result: [String: Any] = ["passed": passed, "checks": checks, "snapshots": snapshots,
                                     "scope": "Only a disposable fixture icon in a separate process is moved."]
        do {
            let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: URL(fileURLWithPath: output), options: .atomic)
            print("Inventory integration test: \(passed ? "PASS" : "FAIL") → \(output)")
        } catch { fputs("Failed to write report: \(error)\n", stderr) }
    }
}
