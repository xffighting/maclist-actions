# MacList 文件上传对话框流程规格

状态：静默重构已实现；真实应用回归暂停
更新时间：2026-07-14

## 1. 一句话目标

用户在微信、邮件或其他应用中打开系统文件选择窗口后，MacList 自动贴附搜索栏，直接模糊搜索本机文件；按回车后把文件交回原窗口，全程不要求额外快捷键、不打开 Finder、不跳转到另一个应用、不依赖剪贴板。

## 2. 真实使用流程

1. 用户在微信或邮件中点击“上传文件 / 添加附件”。
2. macOS 文件选择窗口出现。
3. MacList 自动识别新出现的文件选择窗口，并把轻量搜索栏贴附在该窗口内部上方；用户不需要再按快捷键。
4. 用户直接输入文件名、项目名或路径片段；结果即时模糊匹配。
5. 用户用方向键选择，按回车。
6. 搜索栏收起，原文件选择窗口定位并选中该文件。
7. 开发预览阶段由用户确认原窗口的“打开”；只有真实兼容性回归稳定通过后，才评估自动确认。

`Esc` 只关闭 MacList 浮层，不能关闭原文件选择窗口。

## 3. 明确不做

- 不打开 Finder、Cling、微信、邮件或其他目标应用。
- 不通过 `NSWorkspace.open` 打开命中文件。
- 不复制文件或路径到剪贴板作为主流程。
- 不自动选择收件人、不点击发送、不读取文件正文。
- 不把 GPL 项目 Cling 的源码复制进本仓库。
- 不宣称所有自定义上传窗口都兼容。

## 4. 技术基线

- Swift 6、AppKit，macOS 13 及以上。
- 菜单栏常驻原生应用，无第三方运行时依赖。
- `NSWorkspace` 只记录业务宿主；系统级 focused AX element 与顶部可见窗口负责发现真正的文件面板进程。
- `hostPID`、`dialogOwnerPID`、运行时键盘目标 PID 和 `generation` 分开建模，不能互相代替。
- 每个实际文件面板 PID 拥有独立 `AXObserver`；不支持通知时才使用低频只读轮询。
- 常驻循环只比较轻量焦点快照；深层 AX 分类在专用串行队列执行，不阻塞当前操作。
- 当前实现不注册全局启动快捷键；未来只有在用户明确需要时，才可增加不改变主流程的可选兜底。
- Spotlight 提供文件候选；只使用文件名、路径和时间元数据。
- ApplicationServices Accessibility API 识别并控制当前文件选择窗口。
- 搜索窗口使用非激活式 `NSPanel`，不调用 `NSApp.activate(ignoringOtherApps:)`。

Apple 从 macOS 10.15 起让 Open Panel 由独立进程绘制，外部应用不能取得宿主的 `NSOpenPanel` 对象直接设置 URL。因此主实现采用受控的辅助功能桥接：保存当前窗口 → 关闭浮层 → 等待原窗口自然恢复焦点 → 在原窗口触发“前往文件夹” → 写入绝对路径 → 精确回读选中项。开发预览到此停止，最终“打开”始终由用户点击。

参考：

- [Listary Quick Save & Open](https://www.listary.com/feature/quick-save-and-open)
- [Apple NSOpenPanel](https://developer.apple.com/documentation/appkit/nsopenpanel)
- [Apple AXUIElement](https://developer.apple.com/documentation/applicationservices/axuielement_h)
- [Apple macOS Accessibility Model](https://developer.apple.com/library/archive/documentation/Accessibility/Conceptual/AccessibilityMacOSX/OSXAXmodel.html)

## 5. 模块边界

```text
MacListApp
├── DialogProcessDiscovery   系统焦点与独立 Panel Service 发现
├── FileDialogMonitor         分开监听宿主和真实文件窗口生命周期
├── FileDialogDetector        多证据评分、保存原窗口与双 PID
├── AttachedSearchPanel       贴附文件窗口的非激活搜索栏
├── FileDialogBridge          将命中文件交回原窗口
└── AccessibilityPermission  权限检查与清晰引导

MacListCore
├── SpotlightProvider         本地元数据候选
├── SearchEngine              中英文与子序列模糊排序
└── DialogSelectionPolicy     输入校验与状态/错误语义
```

所有系统调用都要隔离在适配层；状态机和输入校验必须能用假实现测试。

## 6. 权限与失败语义

### 第一次使用

需要 macOS“辅助功能”和文件窗口控制权限。首次显式启动只走系统授权流程；后续不重复提示。MacList 不能绕过 TCC，也不能静默修改系统设置。

### 不在文件选择窗口

MacList 保持安静，不显示独立页面；文件选择窗口出现后才自动贴附搜索栏。

### 自定义或不兼容窗口

显示：`这个上传窗口暂不支持自动选择；原窗口没有被关闭或修改。`

### 文件失效

显示：`文件已移动或删除，请重新搜索。`

任何失败都不得关闭或提交原上传窗口，也不得打开其他应用作为隐式兜底。桥接已经开始后的目录、选择或焦点状态可能保留，真实恢复行为必须等可见回归后再作承诺。

## 7. 测试策略

### 单元测试

- 中文、英文、大小写、宽字符与子序列模糊匹配。
- 文件名命中优先于路径命中；最近文件只作为同分排序因素。
- 目录、缺失文件、空路径不能进入桥接。
- 状态机不会在没有已捕获对话框时提交文件。
- 独立文件面板 PID 即使不同于微信/邮件宿主 PID，也进入候选和独立观察链。
- MacList 自身非激活搜索框取得焦点时，不会误判原窗口关闭。
- 同一应用多窗口时保留当前有效窗口，否则选择聚焦且置信度最高的候选。
- 窄窗口、负坐标副屏和部分离屏布局不能越过可见区域。
- 对话框关闭或切换后，旧 generation、桥接任务和回调全部取消。
- 桥接失败时返回稳定、可展示的错误，不触发备用应用。

### 集成测试

提供 `DialogHarness`，只做一件事：打开标准 `NSOpenPanel`，并显示最终返回 URL。验收顺序：

1. 打开 Harness 的系统文件选择窗口。
2. MacList 自动出现贴附搜索栏，直接搜索一个测试文件。
3. 按回车。
4. 原面板精确选中同一物理文件；用户点击“打开”后 Harness 收到该 URL。
5. 过程中 Finder 和 MacList 主应用都没有被激活到前台。

### 真实场景回归

- 微信：聊天窗口 → 上传文件 → 搜索 → 回车 → 原面板精确选中文件 → 用户点击“打开” → 附件进入待发送区；不自动发送。
- Apple Mail：新邮件 → 添加附件 → 搜索 → 回车 → 原面板精确选中文件 → 用户点击“打开” → 附件出现。
- Outlook：新邮件 → 添加附件 → 搜索 → 回车 → 原面板精确选中文件 → 用户点击“打开” → 附件出现。

每个场景记录：macOS 版本、应用版本、窗口类型、是否成功、失败阶段。未实测的应用只能标记为“待验证”。

## 8. 构建和验证命令

```bash
swift build --package-path app
swift test --package-path app
./app/Scripts/build-app.sh release
./app/Scripts/verify.sh
```

本机只有 Command Line Tools 而缺少 XCTest 时，至少运行无测试框架的 smoke harness 和 release 构建；GitHub Actions 必须在完整 Xcode runner 上执行全部 XCTest。

## 9. 发布门槛

- 主路径中不存在 `NSWorkspace.open`、`activateFileViewerSelecting`、`open -b`、目标应用启动脚本或剪贴板注入。
- 标准 `NSOpenPanel` Harness 完整通过；在用户允许可见测试前保持未验证状态。
- 辅助功能未授权、不在对话框、文件不存在、桥接超时四类失败均通过测试。
- README 第一屏只描述“当前上传窗口内找文件”，旧动作脚本降级为历史/实验内容。
- Apple 风格 Dashboard 同步展示真实通过项与待验证项。
- CI 全绿后才允许打新 tag 和 GitHub Release。

## 10. 待实测问题

- 不支持 AX Window/Sheet 通知的应用是否需要只读轮询兜底。
- 微信和 Outlook 当前版本是否使用标准 Open Panel，或需要单独适配。
- “回车直接确认上传”只有在标准 Harness、微信和邮件均稳定回归后才能启用；当前固定为 `selectOnly`，最后由用户点“打开”。
