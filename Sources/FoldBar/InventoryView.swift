import SwiftUI
import FoldBarCore

struct InventoryView: View {
    @ObservedObject var model: InventoryModel
    @ObservedObject var controller: MenuBarController
    @ObservedObject var settings: Settings

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 7) {
                Text("藏起来的，也能找到。").font(.system(size: 24, weight: .semibold))
                Text("直接在列表中查找和分组，包含刘海后和屏幕外的图标。")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            if !model.hasPermission {
                VStack(alignment: .leading, spacing: 9) {
                    Label("移动图标需要辅助功能权限", systemImage: "hand.raised")
                        .font(.system(size: 12, weight: .semibold))
                    Text("未授权时只显示能确认的当前项目。允许辅助功能后，可识别已收纳和系统图标，并自动移动分组；无需录屏权限。")
                        .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button("打开辅助功能设置") { model.requestPermission() }
                        Button("已授权，重新检查") { model.refresh() }
                    }
                }.padding(14).background(Color.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
            }
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("搜索应用或系统项目", text: $model.search).textFieldStyle(.plain)
                if !model.search.isEmpty { Button { model.search = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain) }
                Button { model.refresh() } label: { Image(systemName: "arrow.clockwise") }.help("刷新图标列表")
                    .disabled(model.movingID != nil)
            }.padding(10).background(.background, in: RoundedRectangle(cornerRadius: 9))
            HStack {
                Toggle("只看未显示的", isOn: $model.onlyObscured).toggleStyle(.checkbox).font(.system(size: 11))
                Spacer()
                Text("\(model.filteredItems.count) / \(model.items.count) 项").font(.system(size: 11)).foregroundStyle(.secondary)
                Button(controller.state.mode == .collapsed ? "展开菜单栏" : "收起菜单栏") {
                    controller.toggle()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { model.refresh() }
                }.disabled(model.movingID != nil)
            }
            Text("勾选后自动移动；「常驻」和「深度收纳」互斥，都不勾选时为普通收纳。")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            if let message = model.message {
                VStack(alignment: .leading, spacing: 7) {
                    Label(message, systemImage: model.isError ? "exclamationmark.triangle" : "checkmark.circle")
                        .foregroundStyle(model.isError ? Color.orange : .teal)
                        .font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
                    if let undo = model.undoDescription { Button(undo) { model.undo() }.disabled(model.movingID != nil).font(.system(size: 11)) }
                }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background((model.isError ? Color.orange : .teal).opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
            }
            if model.items.isEmpty && model.isRefreshing {
                ProgressView("正在同步菜单栏项目…").font(.system(size: 12)).padding(.vertical, 20)
            } else if model.items.isEmpty {
                Label("暂未发现可枚举的菜单栏项目。请退出全屏后刷新；部分系统版本不支持读取独立图标。", systemImage: "info.circle")
                    .font(.system(size: 12)).foregroundStyle(.secondary).padding(.vertical, 20)
            } else if model.filteredItems.isEmpty {
                Text("没有匹配的图标，试试其他关键词或关闭筛选。")
                    .font(.system(size: 12)).foregroundStyle(.secondary).padding(.vertical, 20)
            } else {
                LazyVStack(spacing: 7) {
                    ForEach(model.filteredItems) { item in row(item) }
                }
            }
            Text("仅列出已启用的菜单栏项目，保留被 FoldBar 收纳的图标；页面打开时每 2 秒同步变化。系统固定项目不可移动。")
                .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .onAppear { model.startMonitoring() }
        .onDisappear { model.stopMonitoring() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in model.refresh() }
    }

    private func row(_ item: InventoryItem) -> some View {
        HStack(spacing: 10) {
            Image(nsImage: NSRunningApplication(processIdentifier: item.pid)?.icon ?? NSImage(named: NSImage.applicationIconName)!)
                .resizable().scaledToFit().frame(width: 30, height: 30).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title).font(.system(size: 12, weight: .medium)).lineLimit(1).help(item.title)
                HStack(spacing: 5) {
                    Text(item.group.title)
                    Text("·")
                    Text(ItemInventory.isActuallyVisible(item) ? "当前可见" : "未显示 / 被遮挡")
                        .foregroundStyle(ItemInventory.isActuallyVisible(item) ? Color.secondary : .orange)
                }.font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if model.movingID == item.id { ProgressView().controlSize(.small) }
            if item.isMovable {
                // Derive checks from the last verified group. Never optimistically show a successful move.
                Toggle("常驻", isOn: Binding(
                    get: { item.group == .visible },
                    set: { model.move(item, to: $0 ? .visible : .hidden) }
                ))
                .toggleStyle(.checkbox).fixedSize()
                .help("勾选后移到右侧可见区；取消后移入普通收纳")
                .disabled(model.movingID != nil || !model.hasPermission)
                Toggle("深度收纳", isOn: Binding(
                    get: { item.group == .archive },
                    set: { model.move(item, to: $0 ? .archive : .hidden) }
                ))
                .toggleStyle(.checkbox).fixedSize()
                .help(settings.archiveEnabled ? "勾选后移入深度收纳，并取消常驻；取消后移入普通收纳" : "请先在全局配置中开启深度收纳")
                .disabled(model.movingID != nil || !model.hasPermission || !settings.archiveEnabled)
            } else {
                Text("系统固定项目")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
        .padding(12).background(.background, in: RoundedRectangle(cornerRadius: 10))
    }
}
