import AppKit
import FoldBarCore

/// Opt-in integration test. Temporary H/A items exercise actual WindowServer layout, not a UI mock.
final class MenuBarSelfTest {
    private let controller: MenuBarController
    private let output: String
    private var checks: [[String: Any]] = []
    private var snapshots: [[String: Any]] = []
    private var completion: (() -> Void)?

    init(controller: MenuBarController, output: String) {
        self.controller = controller
        self.output = output
    }

    func start(completion: @escaping () -> Void) {
        self.completion = completion
        later {
            self.snapshot("organizing")
            self.check("initial order", self.controller.arrangementIsValid)
            self.check("organizing reveals both probes", self.visible(self.controller.hiddenProbe) && self.visible(self.controller.archiveProbe))
            self.controller.setMode(.collapsed)
            self.later {
                self.snapshot("collapsed")
                self.check("collapsed hides both probes", !self.visible(self.controller.hiddenProbe) && !self.visible(self.controller.archiveProbe))
                self.check("control survives collapse", self.visible(self.controller.control))
                self.check("collapse accepted", self.controller.state.mode == .collapsed)
                self.check("first collapse completes setup without a separate layout page", self.controller.settings.hasFinishedSetup)
                self.controller.setMode(.expanded)
                self.later {
                    self.snapshot("expanded")
                    self.check("expanded reveals regular group", self.visible(self.controller.hiddenProbe))
                    self.check("expanded keeps archive hidden", !self.visible(self.controller.archiveProbe))
                    self.controller.setMode(.organizing)
                    self.later {
                        self.snapshot("restored")
                        self.check("organizing restores both probes", self.visible(self.controller.hiddenProbe) && self.visible(self.controller.archiveProbe))
                        self.controller.settings.archiveEnabled = false
                        self.later {
                            self.check("disabling archive removes its divider", self.controller.archive == nil)
                            self.check("disabling archive restores archived item", self.visible(self.controller.archiveProbe))
                            self.checkRecovery()
                        }
                    }
                }
            }
        }
    }

    private func checkRecovery() {
        controller.settings.archiveEnabled = true
        // Force an inaccessible separator without touching another app's icon placement.
        controller.divider.length = 10_000
        later {
            self.check("inaccessible divider is detected", self.controller.missingMarkers.contains("① 普通收纳"))
            self.controller.recoverLayout()
            self.later {
                self.snapshot("recovered")
                self.check("recovery puts all markers outside the notch", self.controller.missingMarkers.isEmpty)
                self.check("recovery restores correct boundary order", self.controller.arrangementIsValid)
                self.check("recovery keeps organizing mode", self.controller.state.mode == .organizing)
                self.checkShutdown()
            }
        }
    }

    private func checkShutdown() {
        let items = [controller.control, controller.divider, controller.archive, controller.hiddenProbe, controller.archiveProbe]
        let ids = items.compactMap { $0?.button?.window?.windowNumber }
        controller.shutdown()
        later {
            // AppKit may retain the backing NSWindow after removal; absence from the visible bar is the contract.
            let remaining = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
            let liveIDs = Set(remaining.compactMap { $0[kCGWindowNumber as String] as? Int })
            self.check("shutdown removes owned items from screen", ids.allSatisfy { !liveIDs.contains($0) })
            self.finish()
        }
    }

    private func visible(_ item: NSStatusItem?) -> Bool {
        StatusItemPlacement.isVisible(item)
    }

    private func snapshot(_ name: String) {
        var frames: [String: Any] = [:]
        for (key, item) in [("control", controller.control), ("divider", controller.divider),
                            ("archive", controller.archive), ("hiddenProbe", controller.hiddenProbe), ("archiveProbe", controller.archiveProbe)] {
            if let item, let window = item.button?.window {
                frames[key] = ["frame": NSStringFromRect(window.frame), "visible": visible(item), "length": item.length]
            }
        }
        snapshots.append(["mode": name, "items": frames])
    }

    private func check(_ name: String, _ passed: Bool) { checks.append(["name": name, "passed": passed]) }

    private func later(_ action: @escaping () -> Void) { DispatchQueue.main.asyncAfter(deadline: .now() + 0.7, execute: action) }

    private func finish() {
        let passed = checks.allSatisfy { $0["passed"] as? Bool == true }
        let report: [String: Any] = ["passed": passed, "os": ProcessInfo.processInfo.operatingSystemVersionString,
                                    "checks": checks, "snapshots": snapshots]
        do {
            let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: URL(fileURLWithPath: output), options: .atomic)
            print("FoldBar menu-bar integration test: \(passed ? "PASS" : "FAIL") → \(output)")
        } catch { fputs("Could not write test report: \(error)\n", stderr) }
        completion?()
    }
}
