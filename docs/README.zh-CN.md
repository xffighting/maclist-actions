# MacList Actions

**找到文件，交给目标应用；发送仍由你决定。**

[English](../README.md) · [最新版本](https://github.com/xffighting/maclist-actions/releases/latest)

> [!IMPORTANT]
> 这是非官方社区项目，不包含 Cling，也不隶属于 FuzzyIdeas、The Low-Tech Guys、腾讯、钉钉、Mozilla 或 Listary。Cling 的自定义 Scripts 功能可能需要 Pro 或有效试用。

## 它解决什么

Cling 已经能快速找到文件，但“找到以后交给微信、钉钉或邮件”仍要经过 Finder、拖拽和窗口切换。MacList Actions 把这段流程缩短成一个明确动作，同时保留人工确认发送。

| 动作 | 主窗口快捷键 | 结果 |
|---|---:|---|
| 微信 | Control + Command + W | 复制真实文件并打开微信 |
| 钉钉 | Control + Command + D | 复制真实文件并打开钉钉 |
| Thunderbird | Control + Command + E | 复制真实文件并打开 Thunderbird |
| 资料清单 | Control + Command + L | 复制文件名和完整路径 |

在 Cling 的 Execute script 面板中，也可以直接按 W、D、E 或 L。

## 安装条件

- macOS 14 或更高版本。
- 官方 [Cling 2.6.5](https://github.com/FuzzyIdeas/Cling/releases/tag/v2.6.5)。
- **Cling Pro 或仍有效的试用期，用于自定义 Scripts。**
- 微信、钉钉、Thunderbird 均为独立可选；只安装你实际使用的应用即可。

## 安装

```bash
git clone https://github.com/xffighting/maclist-actions.git
cd maclist-actions
./install.sh
./doctor.sh
```

安装后重启 Cling。安装器会先核对 Cling 版本、Bundle ID、Developer ID 签名与 Team ID，异常时停止。

## 使用

1. 按右 Command + / 打开 Cling。
2. 搜索并选中一个或多个文件。
3. 选择 Scripts 动作，或按 Control + Command + 对应字母。
4. 在目标应用里选择聊天或新建邮件。
5. 按 Command + V。
6. 检查附件和对象后，由你亲自发送。

## 安全边界

本仓库脚本：

- 不选择联系人或收件人；
- 不自动粘贴，不点击发送；
- 不读取文件正文；
- 不包含网络客户端；
- 写入的是真实 macOS 文件 URL，不是路径文字；
- 将回滚状态保存在权限为 0700 的本机目录；
- 会备份同名脚本、六项偏好和 Scripts 目录原权限。

剪贴板里的文件 URL 会保留到下一次被覆盖。目标应用不存在时，文件仍可能已经进入剪贴板。

以上承诺只适用于本仓库脚本，不代表 Cling、微信、钉钉或 Thunderbird 的全部行为。安装器会关闭 Cling 的 Sentry 偏好，但不会删除上游更新或授权组件。

## 验证

```bash
./test.sh
./doctor.sh
./acceptance.sh /path/to/a/known/file
```

本机完整测试会临时覆盖剪贴板；CI 使用明确的无 UI 模式，不触碰剪贴板。

## 卸载

```bash
./uninstall.sh
```

卸载会恢复安装前的同名脚本、偏好和 Scripts 目录权限，不删除 Cling 或搜索索引。从未安装时运行卸载脚本会安全退出，不做任何修改。

## 常见问题

### 这是独立的“Mac 版 Listary”吗？

目前不是。v0.1 依赖 Cling 提供全局入口、文件索引、搜索和结果选择，本项目只提供动作层。

### 会不会上传或自动发送文件？

本仓库脚本不会。它只把本地文件 URL 放入剪贴板并打开目标应用。粘贴、确认和发送都由用户完成。

### 为什么搜不到受保护目录？

这由 Cling 搜索范围和 macOS 权限决定。只有在确实需要搜索 Mail 等受保护位置时，才考虑授予完整磁盘访问权限。

### 为什么不直接发布修改版 Cling？

Cling v2.6.5 的公开工程含本地 WarpDrop 引用，以及尚未完成下游源码和许可证闭环的依赖或二进制。因此本仓库只发布自有动作层，并引导用户安装官方 Cling。

### 支持 Windows 吗？

当前不支持。实现使用了 AppKit 剪贴板、JXA 和 macOS 的 open 命令。

## 参与贡献

阅读 [CONTRIBUTING.md](../CONTRIBUTING.md)。每个新动作都必须说明目标应用、快捷键、联网和内容读取情况、是否可能粘贴或发送，以及回滚方式。

如果它确实减少了你的 Finder 拖拽步骤，可以点一个 Star，让更多 Mac 用户找到它。
