# Command Reopen

**让 macOS 原生 Cmd+Tab 自动恢复最小化和关闭的窗口。**

你按 Cmd+Tab 切到某个应用——什么都没发生。应用在切换器里显示为"活跃"，但窗口还缩在 Dock 里。更糟的情况是你之前关了窗口，现在 Cmd+Tab 切过去，应用激活了，但没有任何窗口出现。

Command Reopen 解决了这个问题。Cmd+Tab 切换应用时，最小化和已关闭的窗口会自动恢复。

🌐 [产品主页](https://commandreopen.com) &nbsp;|&nbsp; [English](README.md)

## 安装

### Mac App Store

[**从 Mac App Store 下载**](https://apps.apple.com/app/id6757333924?ct=cmdr_github_readme&mt=8)

### 下载安装包

**[下载最新版本](https://github.com/Feng6611/mac-command-reopen/releases)**

### 从源码构建

```bash
git clone https://github.com/Feng6611/mac-command-reopen.git
cd mac-command-reopen
open ComTab.xcodeproj
# 选择 "ComTab" scheme → Build & Run (⌘R)
# 需要 Xcode 15+ 和 macOS 12.0+
```

## 功能特点

- Cmd+Tab 自动恢复最小化的窗口
- Cmd+Tab 自动重新打开已关闭的窗口——如果应用没有打开的窗口，会自动创建新窗口
- 无需任何系统权限——不需要辅助功能、不需要屏幕录制、什么都不需要
- 不替换原生 Cmd+Tab 界面——在后台静默工作
- 智能激活追踪——快速来回切换时跳过不必要的恢复
- 支持用户自定义排除列表
- 支持登录时自动启动（macOS 13+）
- 轻量菜单栏应用（<2 MB，几乎零 CPU 占用）
- 开源，代码完全可审计

## macOS 窗口操作快捷键

| 快捷键 | 功能 |
|---|---|
| `Cmd+Tab` | 在应用之间切换 |
| `` Cmd+` `` | 在同一应用的多个窗口间切换 |
| `Cmd+H` | 隐藏当前应用（Cmd+Tab 可以恢复） |
| `Cmd+M` | 最小化当前窗口到 Dock |
| `Cmd+W` | 关闭当前窗口 |
| `Cmd+Option+H` | 隐藏其他所有应用 |
| `Cmd+Tab` → 按住 `Option` → 松开 `Cmd` | 恢复一个最小化窗口（原生方法） |

注意到问题了吗？**Cmd+H**（隐藏）和 Cmd+Tab 配合得很好——窗口可以直接恢复。但 **Cmd+M**（最小化）和 **Cmd+W**（关闭）不行——Cmd+Tab 会切到应用，但窗口不会回来。

这正是 Command Reopen 解决的问题。每次 Cmd+Tab 切换都会自动恢复你的窗口。

## 工作原理

Command Reopen 通过 `NSWorkspace.didActivateApplicationNotification` 监听应用激活事件。当你用 Cmd+Tab 切换到某个应用时，它检测到切换并通过 `NSWorkspace.openApplication(at:configuration:)` 发送恢复请求。这会恢复最小化的窗口并重新创建已关闭的窗口——全部使用标准 macOS API，无需任何特殊权限。

核心逻辑约 300 行，集中在一个文件中：[ActivationMonitor.swift](ComTab/ActivationMonitor.swift)。

## 常见问题

**为什么 Cmd+Tab 不能恢复最小化的窗口？**

macOS 将最小化的窗口视为用户有意"收起"。Cmd+Tab 只切换活跃应用，不会恢复最小化的窗口。唯一的原生方法是 Cmd+Tab → 按住 Option → 松开 Cmd，但这一次只能恢复一个窗口，而且大多数用户根本不知道这个操作。

**Command Reopen 需要什么权限？**

不需要任何权限。它使用沙盒应用可用的 `NSWorkspace` API，无需辅助功能权限、无需屏幕录制权限。

**它会改变 Cmd+Tab 的界面吗？**

不会。原生 Cmd+Tab 切换器完全不变。Command Reopen 在后台静默工作，你不会看到任何视觉变化。

**除了最小化的窗口，已关闭的窗口也能恢复吗？**

可以。如果 Cmd+Tab 切到一个没有打开窗口的应用，Command Reopen 会自动创建新窗口。

## 隐私

Command Reopen 不收集任何数据。所有操作在本地运行。详见 [PRIVACY.md](PRIVACY.md)。

## 许可证

[MIT](LICENSE)
