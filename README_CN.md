<p align="center">
  <img src="docs/icon.svg" alt="Command Reopen" width="128">
</p>

<h1 align="center">Command Reopen</h1>

<p align="center">
  <strong>按 Cmd+Tab，最小化和关掉的窗口自己回来。</strong>
</p>

<p align="center">
  <a href="README.md">English</a> | <b>简体中文</b>
</p>

<p align="center">
  <a href="https://github.com/Feng6611/mac-command-reopen/stargazers"><img src="https://img.shields.io/github/stars/Feng6611/mac-command-reopen?style=flat-square" alt="Stars"></a>
  <a href="https://github.com/Feng6611/mac-command-reopen/releases/latest"><img src="https://img.shields.io/github/v/release/Feng6611/mac-command-reopen?style=flat-square" alt="版本"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue?style=flat-square" alt="License"></a>
  <img src="https://img.shields.io/badge/macOS-13%2B-black?style=flat-square" alt="macOS 13+">
</p>

<p align="center">
  <img src="assets/screenshots-zh.png" alt="Command Reopen：按 Cmd+Tab 从程序坞还原最小化窗口；设置页的排除应用列表；菜单栏菜单" width="900">
</p>

> 为什么做这个 App：[【Command Reopen】我做了一个修复cmd tab体验的Mac App](https://kkuk.dev/zh/posts/command-reopen/)

## 功能

- **最小化的窗口自动还原**：Cmd+Tab 切到应用，窗口自己从程序坞出来。
- **关掉的窗口重新打开**：应用一个窗口都没有时，请它新开一个。
- **原生切换器照旧**：不换切换器，不加浮层，Cmd+Tab 的样子和手感不变。
- **焦点自动交还**：关掉或最小化最后一个窗口后，焦点回到上一个应用。
- **排除应用**：被排除的应用保持系统默认的 Cmd+Tab 行为。
- **菜单栏小工具**：在后台运行，菜单栏图标可以隐藏。

## 快速开始

需要 macOS 13 或更高版本。

**一行命令安装（Direct 版，免费）**

```bash
curl -fsSL https://raw.githubusercontent.com/Feng6611/mac-command-reopen/main/install.sh | bash
```

**安装指定版本，或卸载**

```bash
curl -fsSL https://raw.githubusercontent.com/Feng6611/mac-command-reopen/main/install.sh | bash -s -- --version 1.5.5
curl -fsSL https://raw.githubusercontent.com/Feng6611/mac-command-reopen/main/install.sh | bash -s -- --uninstall
```

**手动下载**：[CommandReopen.dmg](https://github.com/Feng6611/mac-command-reopen/releases/latest/download/CommandReopen.dmg)，把 App 拖进“应用程序”文件夹。

**Mac App Store**：[在 Mac App Store 获取 Command Reopen](https://apps.apple.com/app/apple-store/id6757333924?pt=128417926&ct=readme&mt=8)。

## Direct 版和 Mac App Store 版

| | Direct 版（GitHub） | Mac App Store 版 |
|---|---|---|
| 价格 | 免费 | 终身版，$9.99 一次性买断，可免费试用 7 天 |
| 权限 | 不需要。辅助功能权限可选，用于高级窗口恢复 | 不需要 |
| 窗口恢复 | 发送标准的重新打开请求；允许辅助功能后，Command Reopen 自己还原最小化窗口，不响应该请求的应用也能还原 | 发送标准的重新打开请求 |
| 更新 | 重新运行安装命令 | 通过 App Store 自动更新 |

两个版本的核心功能完全相同。想支持开发者，请选 Mac App Store 版。

## 使用

1. 打开一次 Command Reopen，之后它待在菜单栏里。
2. 最小化（`Cmd+M`）或关闭（`Cmd+W`）一个窗口，再用 Cmd+Tab 切回这个应用，窗口就回来了。
3. 不想处理某个应用，把它加进设置里的“排除 App”。
4. 仅 Direct 版：要用高级窗口恢复，在“设置 › 高级”里允许辅助功能，再打开“使用高级窗口恢复”。还可以打开“恢复所有最小化窗口”和“点按程序坞循环窗口”。

为什么需要它：

| 快捷键 | 效果 | Cmd+Tab 能切回来吗？ |
|---|---|---|
| `Cmd+H` | 隐藏应用 | 能 |
| `Cmd+M` | 窗口最小化至程序坞 | **不能** |
| `Cmd+W` | 关闭窗口 | **不能** |

## 常见问题

**不要权限，它是怎么做到的？**

它通过 `NSWorkspace.didActivateApplicationNotification` 得知你切到了哪个应用，用公开的窗口列表（`CGWindowListCopyWindowInfo`）看有没有可见窗口；一个都没有时，才调用 `NSWorkspace.openApplication(at:configuration:)`，和你点程序坞图标时系统发出的请求相同。代码在 [CmdReopen/Features/Reopen](CmdReopen/Features/Reopen)。

**每次切换都一定有窗口出来吗？**

不一定。应用怎么响应这个请求由它自己决定，和点它的程序坞图标一样。Direct 版的高级窗口恢复能覆盖一部分不响应的应用。

## 支持

- 购买 [Mac App Store 版](https://apps.apple.com/app/apple-store/id6757333924?pt=128417926&ct=readme&mt=8)。
- [请我喝杯咖啡](https://buymeacoffee.com/kkuk)。
- 给仓库点个 Star，或推荐给朋友。

## 关于作者

我是 [chenfeng](https://github.com/Feng6611)，一个人做一些权限需求尽量少的 Mac 小工具，也写了两个 Obsidian 插件：[Open in Terminal](https://github.com/Feng6611/Obsidian-open-in-Teminal) 和 [File Ignore](https://github.com/Feng6611/Obsidian-File-Ignore)。官网：[commandreopen.com](https://commandreopen.com)。

## 隐私

窗口处理都在你的 Mac 上完成。两个版本都会上传匿名的产品分析数据（GitHub 版从 1.5.5 开始），不含 App 名称、窗口标题和个人信息。详见 [PRIVACY.md](PRIVACY.md)。

## 许可证

[MIT](LICENSE)
