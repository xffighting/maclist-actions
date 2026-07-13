# 分发与合规边界

本说明不是法律意见。它记录 MacList 本地定制层当前可验证的发布边界。

## 身份与范围

- MacList Actions 包含独立脚本层，以及不依赖 Cling 的 Swift 搜索核心开发者预览；两者都不是 Cling 官方产品。
- 验证基线为 Cling 2.6.5、Bundle ID com.lowtechguys.Cling、签名 Team ID RDDXV84A73。
- 定制层不修改、不重签 Cling.app。

## 可以分发

- 本仓库中的自有脚本、安装、卸载、检查工具和文档。
- `standalone/` 中的自有 Swift 源码、测试和 CLI 文档。
- 由 `tools/render_media.py` 使用合成文件名生成的 README 媒体。
- 这些文件使用 LICENSE 中的 MIT 许可证。
- 可以提供 Cling 官方发布页链接和独立安装说明。

## 当前不能随包分发

- Cling.app、官方 DMG、上游图标或重新打包的安装镜像。
- 修改、重签或改名后的 Cling 二进制。
- Cling 源码快照或其编译物；公开源码含本地 WarpDrop 引用、商业 SDK 和第三方二进制的来源或许可证缺口，尚不足以证明可提供完整 GPL 对应源码。
- Paddle 标识、用户许可证、索引、缓存、剪贴板内容、安装清单或备份目录。
- 任何暗示 MacList 获得 Cling 官方背书的名称或图标。

## 官方基线校验

- 版本：2.6.5。
- 官方 GitHub 发布页：https://github.com/FuzzyIdeas/Cling/releases/tag/v2.6.5
- DMG 文件名：Cling-2.6.5.dmg。
- 本机校验 SHA-256：0149e811a089ae7894f1f1ccc1154a398a131fb7ae7dfdcb35afb98fabe0124e。
- 本机应用签名主体：Developer ID Application: THE LOW-TECH GUYS SRL (RDDXV84A73)。

Cling 升级后必须重新核对版本、Bundle ID、Team ID、签名、脚本兼容性和联网行为。任一项异常时停止安装。

## 隐私与副作用

- “不读取、不上传文件正文”适用于自有动作脚本和 `standalone/` 开发者预览；第三方目标应用有各自的行为与政策。
- 动作会覆盖剪贴板为真实文件 URL，并打开目标应用；目标应用不存在时，文件仍可能已进入剪贴板。
- 脚本不自动选择收件人或聊天，不执行粘贴和发送。
- 独立核心只扫描用户显式传入的根目录，只保存文件元数据，不复用 Cling 索引、偏好或进程。
- 安装器会写入六项 Cling 偏好并保护 Scripts 目录；卸载器依据安装前快照逐项恢复偏好、同名脚本和原目录权限。
- 备份可能含用户原有同名脚本，只保存在权限为 0700 的本机状态目录，禁止对外打包。
