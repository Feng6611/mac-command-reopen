<p align="center">
  <img src="docs/icon.svg" alt="Command Reopen" width="160">
</p>

<h1 align="center">Command Reopen</h1>

<p align="center">
  <strong>让 macOS 原生 Cmd+Tab 自动恢复最小化和关闭的窗口。</strong>
</p>

<p align="center">
  Cmd+Tab 切到某个应用——什么都没发生，窗口还缩在 Dock 里，或者之前关掉了根本没打开。Command Reopen 让原生 Cmd+Tab 自动把这些窗口恢复回来，像本该的那样工作。
</p>

<p align="center">
  <a href="https://apps.apple.com/app/apple-store/id6757333924?pt=128417926&ct=readme&mt=8">
    <img src="https://tools.applemediaservices.com/api/badges/download-on-the-mac-app-store/black/zh-cn?size=250x83&amp;releaseDate=1742256000" alt="在 Mac App Store 下载" height="54">
  </a>
</p>

<p align="center">
  <sub>想要免费版本？去 <a href="https://github.com/Feng6611/mac-command-reopen/releases">GitHub Releases</a> 下载 DMG · <a href="https://commandreopen.com">产品主页</a> · <a href="README.md">English</a></sub>
</p>


## 功能特点

- **恢复最小化和已关闭的窗口** —— Cmd+Tab 切过去自动恢复；如果应用没有打开的窗口，会自动新建
- **零权限** —— 不需要辅助功能、不需要屏幕录制，什么都不需要
- **保留原生切换器** —— 在 Cmd+Tab 原生界面背后静默工作，界面不变
- **自定义排除列表** —— 你不想被恢复的应用可以排除
- **轻量** —— 菜单栏应用，<2 MB，几乎零 CPU 占用
- **开源**（MIT），代码完全可审计

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

Command Reopen 通过 `NSWorkspace.didActivateApplicationNotification` 监听应用激活事件。当你用 Cmd+Tab 切换到某个应用时，它会先用公开的 CoreGraphics 窗口列表 API（`CGWindowListCopyWindowInfo`）检查这个应用当前是否已经有可见窗口。只有在没有找到可见窗口时，才会通过 `NSWorkspace.openApplication(at:configuration:)` 发送恢复请求。这会恢复最小化的窗口并重新创建已关闭的窗口——全部使用标准 macOS API，无需任何特殊权限。

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
