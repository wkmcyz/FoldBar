# 开发说明

## 目录与构建

| 路径 | 用途 |
| --- | --- |
| `Sources/FoldBarCore/BarState.swift` | 状态转换、刘海可见区与隐藏几何 |
| `Sources/FoldBarCore/InventoryRules.swift` | 窗口过滤、成员校验、分组与移动验收 |
| `Sources/FoldBar/ItemInventory.swift` | 候选窗口扫描、系统名称和坐标转换 |
| `Sources/FoldBar/MenuBarAccessibility.swift` | 后台 AX 查询、一对一窗口匹配 |
| `Sources/FoldBar/InventoryModel.swift` | 搜索、刷新、移动状态与撤销 |
| `Sources/FoldBar/InventoryView.swift` | 图标配置界面 |
| `Sources/FoldBar/ItemMover.swift` | 权限检查、单项移动与位置回读 |
| `Sources/FoldBar/StatusEventRelay.swift` | 自身带标记事件的到达确认 |
| `Sources/FoldBar/MenuBarController.swift` | 分隔项、布局保护与自动收起 |
| `Sources/FoldBar/StatusItemPlacement.swift` | 自身位置恢复与退出位置保存 |
| `Sources/FoldBar/PreferencesView.swift` | 图标配置与全局配置两个页面 |
| `Tests/FoldBarCoreTests/` | 无需图形桌面的核心规则测试 |
| `scripts/` | app 构建、图标生成和图形集成验证 |

项目采用 Swift Package Manager，无第三方依赖。`./scripts/build.sh` 执行 Release 构建、生成图标并签名；输出为 `dist/FoldBar.app`。

## 枚举与刷新

- `CGWindowListCopyWindowInfo(.optionAll)` 只提供候选窗口。窗口存在、层级和尺寸匹配，不代表它仍在菜单栏启用。
- 使用 `AXExtrasMenuBar` 的实际项目校验成员身份，并通过 identifier / description 识别系统项目；已启用的屏幕外项目必须保留。
- AX 在后台按进程串行读取，并设置超时。图标配置页可见时每 2 秒同步，关闭窗口或切到全局配置后停止轮询。
- 合并并发刷新请求；通过 generation 作废移动前的旧快照，避免复选框被中间状态覆盖。
- 单次读取超时不等于项目停用。只回退保留此前已确认、且仍被 FoldBar 分隔项挤出屏幕的项目；明确读到停用时立即移除。
- 搜索必须覆盖显示名、原窗口名称、AX label 和 identifier。只搜索中文显示名会遗漏系统设置中的英文名称。

## 移动和可见性约束

- 每次移动前重新确认窗口 ID 和 PID，避免窗口标识复用；权限不足时不发送控制事件。
- 可见性需同时检查 WindowServer onscreen 状态、屏幕范围及刘海两侧可见区，不能只检查窗口中心。
- 整理期间暂停自动收起；收起前检查分隔顺序；移动后按目标组和实际可见性验收。
- 只有经过实际位置验证的移动才能更新复选框和成功提示；系统事件发送成功不等于移动成功。
- 移动事件中 `0x33` 字段属于未公开兼容细节。事件到达确认不能用任意固定延时替代。
- 涉及溢出处理的改动，必须验证独立进程拥有、实际位于屏幕外的图标可以移回可操作区域。
- 不改写其他 app 偏好，不退出或重启其他 app，不全局修改菜单栏间距。

自身位置恢复仅写 FoldBar 的 `NSStatusItem Preferred Position` 保存键。同一进程重建时使用新的 autosave 标识，避免旧缓存覆盖恢复结果；正常退出保留当前位置。这些约定不能假设跨 macOS 版本稳定，修改后必须在图形桌面验证。

## 测试与签名

```sh
swift test
./scripts/build.sh
./scripts/self-test.sh
./scripts/inventory-test.sh
```

后两项需要先退出正在运行的 FoldBar，并在已登录、解锁的图形桌面执行。独立进程测试仅移动临时 FBT 项，覆盖启用 / 停用同步、屏幕外保留及常驻 → 普通收纳 → 深度收纳 → 常驻。结果写到已被 Git 忽略的 `dist/self-test.json` 和 `dist/inventory-test.json`。

测试父进程与用户独立启动的 app 可能具有不同的辅助功能权限。最终验收必须读回真实应用的权限和界面状态，不能仅凭测试进程授权判断。

构建脚本只在存在唯一有效 Apple Development 身份时自动采用它，否则使用 ad-hoc。可通过 `FOLDBAR_SIGN_IDENTITY` 指定身份。稳定的签名身份有助于保留 TCC 授权；ad-hoc 更新可能需要重新授权。不要提交证书、私钥、个人日志或本机构建缓存。

旧授权记录确实失效时，可用 `tccutil reset Accessibility com.wkm.foldbar` 仅撤销 FoldBar 的授权，再让用户从当前 app 重新申请并手动开启。不要直接修改 TCC 数据库；无证据表明授权损坏时不要重置。参考 [Apple DTS 对 TCC 与签名的说明](https://developer.apple.com/forums/thread/730043)。

## 发布检查

- 维护 README 中的功能范围和已验证 / 未验证边界。
- 检查实际 Git 暂存内容；排除 `.build/`、`dist/`、本机路径、日志、凭据和个人调试记录。
- 提交使用 GitHub noreply 邮箱，避免公开本机工作邮箱。
- 公开截图仅展示产品功能；发布前检查画面中没有私人内容。
- 推送后读回远端提交、默认分支和许可证，不以本地提交成功替代发布确认。
