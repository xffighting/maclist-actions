# MacList

**就在文件上传窗口里搜索，不切应用。**

[English](../README.md) · [流程规格](FILE_DIALOG_FLOW_SPEC.md) · [GitHub Actions](https://github.com/xffighting/maclist-actions/actions)

> [!IMPORTANT]
> 原生 Mac App 目前是开发预览版。自动监听、贴附式搜索栏、模糊搜索和安全回填桥接已经实现并通过静默测试；按照用户要求，新的微信、Apple Mail、Outlook 可视化回归暂时没有运行，因此这里不会写“已经兼容”。

## 它解决哪个时刻

你已经在微信聊天或邮件草稿里，点击了“上传文件 / 添加附件”。最麻烦的不是打开应用，而是在系统文件窗口里重新想目录、翻 Finder、找那个大概记得名字的资料。

MacList 只盯住这个时刻：

1. 你在微信或邮件点击“上传文件”。
2. macOS 文件选择窗口出现。
3. MacList 自动识别，并把一条安静的搜索栏贴在这个窗口内部。
4. 直接输入模糊文件名、项目名或路径片段。
5. 按回车，文件在原上传窗口里被精确定位并选中。开发预览阶段由你最后点击“打开”。

主流程不再要求 `⌥Space`，不打开 Finder，也不先跳到一个独立的 MacList 页面。

## 当前完成度

| 能力 | 状态 | 证据 |
|---|---|---|
| 文件窗口自动监听 | 已实现、静默验证通过 | 系统级焦点发现；宿主 PID 与文件面板 PID 分离；release 构建通过 |
| 贴附式非激活搜索栏 | 已实现 | 布局和生命周期测试；已删除居中启动页路径 |
| 中英文模糊搜索 | 已实现 | 无测试框架 smoke test + XCTest |
| Spotlight 本地元数据候选 | 已实现 | 只使用文件名、路径、时间，不读正文 |
| 精确回填原文件窗口 | 已实现安全门禁 | 精确核对物理文件；预览版不自动点最终“打开” |
| 标准 `NSOpenPanel` 可视化回归 | 暂停 | 需要用户明确允许后再运行 |
| 微信 / Apple Mail / Outlook 回归 | 尚未验证 | 通过前不做兼容承诺 |
| 签名、公证、可下载安装包 | 尚未提供 | 当前从源码构建 |

仓库中的 Cling 动作脚本和 Standalone CLI 是早期原型，仍保留用于追溯，但已经不是产品主流程。

## 为什么必须做成原生小程序

Skill 可以负责安装说明、诊断和验证，但不能持续监听 macOS 窗口、显示不激活自身应用的贴附面板，也不能安全控制另一个应用打开的系统文件窗口。因此：

- 核心体验：Swift + AppKit 原生菜单栏 App；
- 可选辅助：未来再提供安装/诊断 Skill。

## 技术结构

```text
MacListApp
├── DialogProcessDiscovery   从系统焦点发现独立文件面板进程
├── FileDialogMonitor         分开监听宿主和真实文件面板 PID
├── FileDialogDetector        用聚焦、可见性和文件语义评分识别
├── SearchPanelController     贴附紧凑的非激活搜索栏
├── FileDialogBridge          把精确文件交回原窗口
└── AccessibilityPermission  不绕过 macOS TCC

MacListCore
├── DialogObservation         纯状态机与贴附布局
├── SearchEngine              确定性的模糊排序
├── SpotlightProvider         本地元数据候选
└── DialogSelectionPolicy     路径验证与失败保护
```

macOS 10.15 以后，Open Panel 由独立进程绘制，外部应用拿不到宿主的 `NSOpenPanel` 对象。MacList 因此只能使用经过用户授权的系统辅助功能接口，并且在无法确认窗口或文件时安全停止。

## 静默构建与验证

需要 macOS 13+ 和 Swift 6：

```bash
git clone https://github.com/xffighting/maclist-actions.git
cd maclist-actions
./app/Scripts/verify.sh
```

这个命令只做静默检查：

- 运行状态机、布局、搜索和路径策略测试；
- 本机有完整 Xcode 时运行 XCTest；
- 构建 release 二进制和本地 `MacList.app`；
- 校验 plist 与签名；
- 不启动 MacList，不打开微信/邮件，不发送键盘事件。

单独命令：

```bash
swift build --package-path app
./app/Scripts/smoke-test.sh
./app/Scripts/build-app.sh release
```

## 隐私与安全边界

- 不上传文件、无遥测、无账号、无 API Key；
- 不读取文档正文，只搜索文件名、路径和时间；
- 不打开 Finder，不切微信/邮件，不使用剪贴板注入或 AppleScript；
- 不选择联系人、收件人或聊天，不自动发送；
- 首次启动只走 macOS 正常的辅助功能授权；文件窗口控制权限从菜单栏明确申请，程序不能绕过；
- 目录、空路径、已删除文件不能进入回填；
- 预览版只负责精确选中并回读同一个物理文件，最终“打开”由用户确认；
- Save 窗口不得自动提交，更不能自动覆盖文件。

## 调研依据

- [Listary Quick Save & Open](https://www.listary.com/feature/quick-save-and-open)：产品时刻参考；
- [Cling](https://github.com/FuzzyIdeas/Cling)：本地搜索体验与索引参考，GPL-3.0 源码不复制进本 MIT 项目；
- [Dialog Jumper](https://github.com/limars874/dialog-jumper-macos)：MIT 的 macOS 文件窗口识别实验；
- [Peekaboo](https://github.com/openclaw/Peekaboo)：成熟的 MIT 辅助功能自动化与 AX 元素重解析参考；
- [LeaderKey](https://github.com/mikker/LeaderKey)：非激活 AppKit Panel 参考。

完整产品边界和发布门槛见 [文件上传窗口流程规格](FILE_DIALOG_FLOW_SPEC.md)。

## 常见问题

### 微信点击上传后会自动出现吗？

这是现在唯一正确的主流程。代码已经改为自动监听，不再依赖快捷键；但新的真实微信回归按要求暂停，未通过前不会写“已兼容微信”。

### 为什么要辅助功能权限？

macOS 不允许外部应用直接取得微信/邮件的 `NSOpenPanel` 对象。要在不切应用、不用剪贴板的情况下识别窗口、写入路径并核对文件，只能走用户授权的系统 Accessibility API。

### 会读取或上传我的文件吗？

不会。MacList 只搜索本机元数据；最终文件仍由你已经打开的系统上传窗口接收。

## 许可证

MacList 自有代码采用 MIT 许可证，不隶属于 Apple、Listary、腾讯、Microsoft、FuzzyIdeas 或其他参考项目。详情见 [NOTICE](../NOTICE.md) 和 [COMPLIANCE](../COMPLIANCE.md)。
