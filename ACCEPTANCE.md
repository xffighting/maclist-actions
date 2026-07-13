# MacList v0.2.0 验收记录

验收日期：2026-07-13
验收状态：Release Candidate；以对应提交的 GitHub Actions 全绿和 Release 资产回读为最终发布门槛。

## 一句话结论

v0.2.0 已形成两条边界清楚的产品线：可直接使用的 Cling 文件动作，以及不依赖 Cling、只索引用户显式授权目录的 Standalone Core 开发者预览。两者都坚持本地优先，不读取文档正文，不自动粘贴或发送。

## 交付范围

### Cling Actions · Stable

- 微信、钉钉、Thunderbird、Apple Mail、Outlook：复制真实文件 URL 后，只打开目标应用。
- 复制资料清单：生成可粘贴的文件名和路径文本。
- Apple Mail 快捷键：`Control + Command + M`。
- Outlook 快捷键：`Control + Command + O`。
- 安装、升级和卸载继续保留原有脚本、偏好与目录权限的回滚快照。

### Standalone Core · Developer Preview

- Swift Package 提供 `MacListCore` 库和 `maclist` 命令行工具。
- 只接受显式授权的绝对目录；隐藏文件和符号链接不进入索引。
- 索引仅保存路径与基础元数据，不保存文档正文。
- 支持确定性的模糊排序、短中文查询和 JSON 输出。
- `doctor` 检查隐私模型、索引格式、文件权限、授权根目录和范围边界。
- 这是搜索内核与 CLI 预览，不是完整的 Listary 图形界面替代品。

## 自动验收矩阵

GitHub Actions 在每次 push、pull request 和手动触发时并行执行以下门禁：

| 门禁 | 运行环境 | 通过标准 |
| --- | --- | --- |
| Cling actions | `macos-latest`，无界面模式 | 脚本语法与元数据正确；快捷键唯一；邮件动作不模拟键盘、不粘贴、不发送；安装升级卸载和权限回滚全部通过 |
| Standalone unit | `macos-latest` 完整 Xcode | `swift test --package-path standalone` 全部通过 |
| Standalone smoke | `macos-latest` | 独立编译库和 CLI；授权范围、隐藏文件、符号链接、正文隔离、中文与模糊查询、doctor 和权限断言全部通过 |
| Release media | `macos-latest` Vision OCR | Social Preview 为 1280×640 且小于 1 MB；逐帧检查 PNG/GIF，不含本机路径、邮箱、IP、手机号、用户名或已知私有业务词 |
| Repository hygiene | `macos-latest` | YAML 可解析；Markdown/HTML 本地链接存在且不越界；无绝对 macOS 用户路径、私钥或 credential-shaped 字符串；版本元数据一致 |

本机 Command Line Tools 缺少 XCTest，因此 Standalone 单元测试不以本机结果代替 CI；GitHub 的完整 Xcode runner 是该门禁的权威环境。无需 XCTest 的 `standalone/smoke-test.sh` 同时保留，避免只验证“能跑测试框架”而没有验证真实 CLI 行为。

## 已核验的安全边界

- 邮件与聊天动作只准备剪贴板中的文件 URL，并打开对应应用。
- 脚本没有网络客户端调用，也没有 `System Events`、键盘模拟、收件人、草稿、粘贴或发送逻辑。
- Apple Mail 已能由本机系统定位；当前验收机未安装 Outlook，因此 Outlook 的真实窗口粘贴仍是发布后需在安装了 Outlook 的机器上补测的明确差距。
- Standalone Core 不跟踪整台电脑，不扫描未授权目录，不跟随符号链接，不读取文件内容。
- GitHub Social Preview 只能通过仓库设置页面上传；图片文件进入源码和 CI 并不等于 GitHub 页面已经启用，发布时必须单独回读 `usesCustomOpenGraphImage=true`。

## 既有 Cling 基线

- Cling 2.6.5 安装在 `/Applications/Cling.app`，Bundle ID 为 `com.lowtechguys.Cling`。
- 既有实测目标为 `README.md`；在 283,348 条已加载索引中可检索。
- 连续 20 次最终复验 P95：搜索 7.7 ms，本机往返 24.0 ms。
- 该数字仅代表一台验收机，不作为跨设备性能承诺。
- v0.1 的真实卸载、恢复和重新安装闭环已通过；v0.2 继续由自动化回归覆盖同一回滚模型及新增邮件动作的升级场景。

## 发布前必须回读

- 对应提交的四个 GitHub Actions job 全部成功。
- `v0.2.0` tag 指向已验收的提交。
- Release 同时包含 ZIP 和 SHA-256 文件；重新下载后的摘要与发布值一致。
- GitHub 仓库页的自定义 Social Preview 已启用并能回读。
- README 中 Stable 与 Developer Preview 的措辞、GIF、快捷键和已知边界与本记录一致。

## 明确不在本次承诺内

- 不替用户授予完整磁盘访问权限。
- 不自动选择聊天、收件人或邮件草稿，不粘贴、不发送。
- 不承诺 Cling 的 Pro/试用授权能力。
- 不分发 Cling 二进制、DMG 或上游源码快照。
- 不把 Standalone Core 描述为已经完成的原生搜索 App。
