# Command Reopen

**Command Reopen** 让你可以通过 `Command+Tab` 重新打开已关闭或最小化的窗口。

macOS 原生的 `Command+Tab` 无法唤起那些已经关闭窗口但仍在后台运行的应用（点击 Dock 图标通常可以），或者已经最小化的窗口。这款小工具完美解决了这个问题。

[![Download on the Mac App Store](https://developer.apple.com/assets/elements/badges/download-on-the-mac-app-store.svg)](https://apps.apple.com/app/idAPP_ID)

**[下载最新版本](https://github.com/Feng6611/mac-command-reopen/releases)**

### 功能特点

- 使用 `Command+Tab` 切换应用时，自动重新打开已关闭的主窗口
- 使用 `Command+Tab` 切换应用时，自动恢复最小化的窗口
- **v1.0.0：**新增智能窗口检测：若应用已有可见窗口则跳过重复唤起
- 不需要辅助功能权限
- 为了提升可见窗口检测准确性（基于 CGWindowList），macOS 可能会请求你授予“屏幕录制”权限（可选）
- 不修改或替换原生的 `Command+Tab` 界面与行为，静默运行
- **系统要求：** macOS 12.0 及以上
