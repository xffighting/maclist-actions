# MacList v0.1 验收记录

验收日期：2026-07-11

## 运行基线

- 官方 Cling 2.6.5 安装在 /Applications/Cling.app。
- Bundle ID：com.lowtechguys.Cling。
- Team ID：RDDXV84A73。
- Developer ID 深度签名校验通过。
- 首次设置已完成，使用 Utility 模式；默认全局入口为右 Command + /。
- Sentry 已关闭，外置盘自动索引已关闭。

## 搜索

- 已知目标：README.md。
- 目标在 283,348 条已加载索引中可检索。
- 连续 20 次最终复验 P95：搜索 7.7ms，本机往返 24.0ms。
- 后台索引期间的前一轮 P95 为 23.0ms / 24.8ms，说明当前机器的端到端结果稳定在约 25ms。
- 验收时 Library 范围仍在后台继续建立索引；Home、Applications、System 和 Root 已有持久索引。

## 文件动作

- 微信工作流用 README.md 实测退出码为 0。
- 剪贴板包含 1 个真实文件，类型同时包含 public.file-url 和 NSFilenamesPboardType。
- 微信已打开；没有选择聊天、粘贴或发送。
- doctor 已确认微信、钉钉和 Thunderbird 均可由系统定位；它们在公共版本中是互相独立的可选动作。
- 自动测试确认四个动作的语法、元数据、文件 URL 和无网络客户端约束。

## 回滚

真实执行卸载后：

- MacList 脚本剩余 0 个。
- 六项定制偏好剩余 0 个，恢复到安装前状态。
- Cling、283,348 条已加载索引和目标文件搜索继续可用。

随后重新安装并重启 Cling，doctor 的必需检查全部通过。沙箱回归还验证了：

- 重复安装幂等。
- 安装后脚本被改动时拒绝覆盖。
- 原有同名脚本可恢复。
- 原有 Boolean 偏好可恢复。
- 原有 Scripts 目录权限可恢复。
- 新增脚本和私有回滚状态会在恢复后删除。
- 从未安装时执行卸载不会改变 Cling 偏好。

## 已知边界

- 未替用户授予完整磁盘访问权限；需要搜索受保护目录时，由用户在系统设置中决定。
- 没有在聊天或邮件窗口里执行真实粘贴和发送，避免误发。
- Cling 的 Scripts 功能可能受 Pro 或试用状态限制。
- 当前公开源码无法形成可证明完整的 GPL 对应源码构建，因此交付包只包含独立 Customization 层，不包含 Cling 二进制、DMG 或上游源码快照。
- 当前系统上，Cling 位于 ~/Applications 时启动会卡住；/Applications 已实测正常。
