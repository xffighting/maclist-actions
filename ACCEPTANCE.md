# MacList 原生预览验收记录

验收日期：2026-07-14

验收范围：仅静默测试与静态安全检查

结论：**原生架构重构已通过本机无界面门禁；真实微信、邮件兼容性尚未验收，不允许据此发布正式版。**

## 本阶段修正了什么

- 主流程不再依赖快捷键或独立启动页：文件选择窗口出现后自动贴附搜索栏。
- 不再假设“微信 PID 就是文件面板 PID”。系统级焦点发现会分别保存宿主应用、文件面板拥有者和当前键盘目标。
- 实际文件面板 PID 拥有独立 AXObserver；旧窗口注册会在切换和关闭时移除。
- 深层 AX 分类移到专用串行队列；常驻轮询只做轻量焦点快照，避免阻塞当前电脑操作。
- 对话框使用多证据评分：聚焦、可见、非最小化、文件容器、文件 URL/路径语义和默认动作。
- 搜索浮层不加入所有 Space，不调用应用激活、停用、Finder、剪贴板或 AppleScript。
- `dialogID + generation` 让关闭窗口后的旧异步任务全部失效。
- 回填事务区分 `hostPID`、`dialogOwnerPID`、运行时事件目标，并在每个阶段重新验证原面板。
- 开发预览默认只精确选中文件，主路径不存在最终 Open、Save 或 Send 调用；真实窗口误触风险仍待可见回归确认。

## 本机静默门禁

`./app/Scripts/verify.sh` 已完成：

- 模糊搜索 smoke：通过。
- 对话框识别、PID 候选、焦点保留、会话代次和多屏布局 smoke：通过。
- 文件路径、目录拒绝、物理文件身份和桥接计划 smoke：通过。
- Swift release 构建：通过。
- `MacList.app` 与测试 Harness 的 plist、临时签名校验：通过。
- `--doctor`：以命令行方式完成，没有启动图形界面。
- 禁用流程静态扫描：未发现 `NSApp.activate`、`NSApp.deactivate`、Finder 打开、剪贴板注入或旧快捷键入口。
- 进程回读：测试结束后没有 MacList 或 DialogHarness 图形进程。

本机只有 Command Line Tools，缺少 XCTest 模块；完整 XCTest 由 GitHub Actions 的 Xcode runner 执行。本机 smoke 不能替代真实应用回归。

## 明确没有做

- 没有启动 MacList 图形界面。
- 没有打开 DialogHarness、微信、Apple Mail 或 Outlook。
- 没有发键盘事件、抢焦点、切换 Space 或改变当前窗口。
- 没有声称微信、Apple Mail 或 Outlook 已兼容。
- 没有开启自动点击文件面板最终“打开”。
- 没有创建新 tag、GitHub Release、签名公证安装包。

## 下一道发布门槛

用户允许可见测试后，按顺序验证：

1. 标准 `NSOpenPanel`：自动贴附、输入焦点、精确选中、关闭和切换窗口。
2. 微信：点击上传后自动出现；选中文件进入原面板；不自动发送。
3. Apple Mail 与 Outlook：添加附件流程相同，逐个记录应用版本与失败阶段。
4. 连续打开、关闭、切换十次，确认无残留浮层、无旧回调、无跨 Space 漂移。
5. 只有上述回归稳定通过，才评估是否把“最终打开”从人工确认改为自动确认。

## 旧原型边界

`scripts/` 的 Cling 动作和 `standalone/` 的 CLI 仍作为早期研究资产保留，但不代表当前原生产品流程，也不能作为微信自动唤起的验收证据。
