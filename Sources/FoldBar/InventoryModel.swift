import AppKit
import Combine
import FoldBarCore

@MainActor
final class InventoryModel: ObservableObject {
    @Published private(set) var items: [InventoryItem] = []
    @Published private(set) var hasPermission = ItemMover.isTrusted
    @Published private(set) var movingID: CGWindowID?
    @Published private(set) var message: String?
    @Published private(set) var isError = false
    @Published private(set) var undoDescription: String?
    @Published var search = ""
    @Published var onlyObscured = false
    private let controller: MenuBarController
    private let mover = ItemMover()
    private var undoAction: (item: InventoryItem, group: ItemGroup)?
    private var knownActive = Set<InventoryIdentity>()
    private var metadataCache: [InventoryIdentity: MenuExtraMetadata] = [:]
    private var pollingTimer: Timer?
    @Published private(set) var isRefreshing = false
    private var refreshAgain = false
    private var generation = 0

    init(controller: MenuBarController) {
        self.controller = controller
        // Capture the enabled inventory before a later startup collapse can move it offscreen.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.refresh() }
    }

    func startMonitoring() {
        guard pollingTimer == nil else { return }
        refresh()
        // Only poll while the icon page is displayed. Owners' AX calls run off the UI thread with bounded timeouts.
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.controller.settingsAreVisible?() == true, self.controller.settingsTab == 0 else { return }
                self.refresh()
            }
        }
        timer.tolerance = 0.3
        RunLoop.main.add(timer, forMode: .common)
        pollingTimer = timer
    }

    func stopMonitoring() { pollingTimer?.invalidate(); pollingTimer = nil }

    deinit { pollingTimer?.invalidate() }

    var filteredItems: [InventoryItem] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return items.filter {
            // The panel's Chinese names can differ from System Settings. Keep native names and AX aliases searchable too.
            (!onlyObscured || !ItemInventory.isActuallyVisible($0)) &&
                (query.isEmpty || [$0.title, $0.application, $0.windowTitle, $0.accessibilityLabel, $0.accessibilityIdentifier]
                    .contains { $0.localizedCaseInsensitiveContains(query) })
        }
    }

    func refresh() {
        hasPermission = ItemMover.isTrusted
        // A system drag has intermediate positions. Keep the checks stable until the move has been verified.
        guard movingID == nil else { return }
        guard !isRefreshing else { refreshAgain = true; return }
        isRefreshing = true
        let requestGeneration = generation
        let candidates = ItemInventory.scan()
        Task {
            defer {
                isRefreshing = false
                if refreshAgain { refreshAgain = false; refresh() }
            }
            let snapshots = await MenuBarAccessibility.snapshots(for: Set(candidates.map(\.pid)))
            guard requestGeneration == generation, movingID == nil else { return }
            // Re-read frames after AX messaging so dynamic-width icons don't leave us using an old menu-bar layout.
            applySnapshot(ItemInventory.scan(), snapshots: snapshots)
        }
    }

    private func applySnapshot(_ candidates: [InventoryItem], snapshots: [pid_t: MenuExtrasSnapshot]) {
        let divider = ItemInventory.frame(of: controller.divider)
        let archive = ItemInventory.frame(of: controller.archive)
        let enlarged = [divider, archive].compactMap { $0 }.filter { $0.width > BarGeometry.dividerWidth * 2 }
        let liveIDs = Set(candidates.map(\.identity))
        knownActive.formIntersection(liveIDs)
        metadataCache = metadataCache.filter { liveIDs.contains($0.key) }
        let matches = MenuBarAccessibility.matches(items: candidates, snapshots: snapshots)
        items = candidates.compactMap { item in
            var item = item
            let metadata = matches[item.identity]
            let evidence: InventoryRules.MembershipEvidence = metadata != nil ? .active
                : (snapshots[item.pid]?.readable == true ? .inactive : .unavailable)
            let displaced = enlarged.contains { item.frame.maxX <= $0.minX + 2 && abs(item.frame.midY - $0.midY) < 12 }
            guard InventoryRules.isEnabledMenuItem(onScreen: item.isOnScreen, evidence: evidence,
                                                  previouslyActive: knownActive.contains(item.identity), displacedByFoldBar: displaced) else {
                knownActive.remove(item.identity)
                metadataCache.removeValue(forKey: item.identity)
                return nil
            }
            if let metadata { metadataCache[item.identity] = metadata }
            if let metadata = metadata ?? (evidence == .unavailable ? metadataCache[item.identity] : nil) {
                item.accessibilityIdentifier = metadata.identifier
                item.accessibilityLabel = metadata.label
                item.accessibilityFrame = matches[item.identity]?.frame // Cached labels are reusable; old geometry is not.
            }
            guard !item.isUnidentifiedSystemItem else { return nil }
            knownActive.insert(item.identity)
            if let divider { item.group = InventoryRules.group(of: item.frame, divider: divider, archive: archive) }
            return item
        }
    }

    func requestPermission() { ItemMover.requestPermission() }

    func move(_ item: InventoryItem, to group: ItemGroup, isUndo: Bool = false) {
        guard movingID == nil else { return }
        generation += 1
        movingID = item.id
        message = nil
        controller.isManagingInventory = true
        Task {
            defer {
                movingID = nil
                controller.isManagingInventory = false
                refresh()
            }
            do {
                try await mover.move(item, to: group, controller: controller)
                if let index = items.firstIndex(where: { $0.identity == item.identity }), var moved = ItemInventory.current(item) {
                    moved.group = group
                    moved.accessibilityIdentifier = item.accessibilityIdentifier
                    moved.accessibilityLabel = item.accessibilityLabel
                    items[index] = moved
                    metadataCache.removeValue(forKey: item.identity)
                }
                isError = false
                message = "\(item.title) 已移到\(group.title)。\(group == .visible ? "现在可以在右上角点击它。" : "点击「收起菜单栏」后隐藏。")"
                if isUndo {
                    undoAction = nil
                    undoDescription = nil
                } else if item.group != group {
                    undoAction = (item, item.group)
                    undoDescription = "撤销「\(item.title)」的分组"
                }
            } catch {
                isError = true
                message = error.localizedDescription
            }
        }
    }

    func undo() {
        guard let undoAction else { return }
        move(undoAction.item, to: undoAction.group, isUndo: true)
    }
}
