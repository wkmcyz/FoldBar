import SwiftUI

private let accent = Color(nsColor: NSColor(name: nil) { appearance in
    appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        ? NSColor(calibratedRed: 0.68, green: 0.66, blue: 1, alpha: 1)
        : NSColor(calibratedRed: 0.35, green: 0.36, blue: 0.87, alpha: 1)
})

struct PreferencesView: View {
    @ObservedObject var controller: MenuBarController
    @ObservedObject var settings: Settings
    @ObservedObject var inventory: InventoryModel
    private var selection: Int { controller.settingsTab }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if selection == 0 { InventoryView(model: inventory, controller: controller, settings: settings) }
                    else { preferences }
                    if let notice = controller.notice { message(notice, symbol: "exclamationmark.triangle", color: .orange) }
                }
                .padding(30)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .tint(accent)
        .frame(minWidth: 740, minHeight: 610)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable().frame(width: 54, height: 54).accessibilityHidden(true)
            .padding(.bottom, 6)
            Text("FoldBar").font(.system(size: 22, weight: .bold, design: .rounded))
            Text("折叠栏").foregroundStyle(.secondary).font(.system(size: 12))
            VStack(spacing: 5) {
                navigationRow("图标配置", symbol: "square.grid.2x2", value: 0)
                navigationRow("全局配置", symbol: "slider.horizontal.3", value: 1)
            }.padding(.top, 24)
            Spacer()
            Label("轻一点，专注一点", systemImage: "leaf")
                .font(.system(size: 10)).foregroundStyle(.secondary)
            Text("v1.3.1 · 原生 macOS app").font(.system(size: 10)).foregroundStyle(.tertiary)
        }
        .padding(20)
        .frame(width: 164, alignment: .leading)
        .background(.ultraThinMaterial)
    }

    private func navigationRow(_ title: String, symbol: String, value: Int) -> some View {
        Button { controller.settingsTab = value } label: {
            Label(title, systemImage: symbol)
                .font(.system(size: 13, weight: selection == value ? .semibold : .regular))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10).padding(.vertical, 10)
                .background(selection == value ? accent.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 8))
                .foregroundStyle(selection == value ? accent : .primary)
        }.buttonStyle(.plain)
    }

    private var preferences: some View {
        Group {
            VStack(alignment: .leading, spacing: 8) {
                Text("用起来，刚刚好。").font(.system(size: 24, weight: .semibold))
                Text("让收纳配合你的工作节奏。").font(.system(size: 13)).foregroundStyle(.secondary)
            }
            VStack(spacing: 0) {
                settingRow("自动收起", detail: "展开后自动收起，移动图标或操作菜单时暂停。") { Toggle("自动收起", isOn: $settings.autoHide).labelsHidden() }
                if settings.autoHide {
                    Divider().padding(.horizontal, 16)
                    HStack {
                        Text("等待时间").font(.system(size: 12))
                        Spacer()
                        Picker("等待时间", selection: $settings.delay) {
                            ForEach([5.0, 10.0, 15.0, 30.0, 60.0], id: \.self) { value in Text("\(Int(value)) 秒").tag(value) }
                        }.labelsHidden().frame(width: 100)
                    }.padding(16)
                }
                Divider().padding(.horizontal, 16)
                settingRow("深度收纳", detail: "开启后，可在图标配置中勾选「深度收纳」。") { Toggle("深度收纳", isOn: $settings.archiveEnabled).labelsHidden() }
                Divider().padding(.horizontal, 16)
                settingRow("启动后收起", detail: "首次收起后生效；启动时等待 10 秒再收起。") { Toggle("启动后收起", isOn: $settings.startCollapsed).labelsHidden() }
            }.background(.background, in: RoundedRectangle(cornerRadius: 12))
            Button(controller.isRecoveringLayout ? "正在恢复…" : "恢复菜单栏位置") { controller.recoverLayout() }
                .disabled(controller.isRecoveringLayout || controller.isManagingInventory)
                .help("控制图标不可见时可恢复位置；恢复会改变分组边界")
            if let warning = controller.layoutWarning { message(warning, symbol: "exclamationmark.triangle", color: .orange) }
            VStack(spacing: 0) {
                settingRow("全局快捷键", detail: "⌃ ⌥ B · 展开或收起收纳组") { Toggle("全局快捷键", isOn: $settings.shortcutEnabled).labelsHidden() }
                Divider().padding(.horizontal, 16)
                settingRow("登录时启动", detail: "登录这台 Mac 时自动打开 FoldBar。") {
                    Toggle("登录时启动", isOn: Binding(get: { settings.loginEnabled }, set: { settings.setLoginEnabled($0) })).labelsHidden()
                }
            }.background(.background, in: RoundedRectangle(cornerRadius: 12))
            if settings.shortcutEnabled && !controller.shortcutAvailable {
                message("⌃ ⌥ B 注册失败，可能已被其他 app 占用。菜单栏按钮仍可使用。", symbol: "keyboard", color: .orange)
            }
            if let error = settings.loginMessage { message(error, symbol: "info.circle", color: .orange) }
            message("识别已收纳和系统图标、自动移动需要辅助功能权限；不需要录屏权限。", symbol: "checkmark.shield", color: .teal)
        }
    }

    private func settingRow<Control: View>(_ title: String, detail: String, @ViewBuilder control: () -> Control) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 12, weight: .medium))
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            control().toggleStyle(.switch).controlSize(.small)
        }.padding(16)
    }

    private func message(_ text: String, symbol: String, color: Color) -> some View {
        Label(text, systemImage: symbol).font(.system(size: 11)).foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true).padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(color.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
    }
}
