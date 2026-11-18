<p align="center">
  <img src="docs/icon.svg" width="96" height="96" alt="Command Reopen icon">
</p>

<h1 align="center">Command Reopen</h1>

<p align="center">
  Bring back minimized and closed windows on Cmd+Tab.
</p>

<p align="center">
  <a href="README_CN.md">简体中文</a> | <b>English</b>
</p>

<p align="center">
  <a href="https://apps.apple.com/app/apple-store/id6757333924?pt=128417926&ct=readme&mt=8">
    <img src="https://tools.applemediaservices.com/api/badges/download-on-the-mac-app-store/black/en-us?size=250x83&amp;releaseDate=1742256000" alt="Download on the Mac App Store" height="54">
  </a>
</p>

<p align="center">
  <img src="assets/screenshots-en.png" width="800" alt="Command Reopen preview">
</p>

> **Get Command Reopen on the Mac App Store**
>
> Command Reopen is available on the [Mac App Store](https://apps.apple.com/app/apple-store/id6757333924?pt=128417926&ct=readme&mt=8). It offers a lightweight, simple setup with no Accessibility permission required, includes automatic updates, and buying it supports ongoing development.
>
> Prefer free and open source? The Direct edition is available via [GitHub Releases](https://github.com/Feng6611/mac-command-reopen/releases/latest). It adds optional Accessibility settings in Settings › Advanced to help restore minimized windows for some apps that ignore standard system reopen events. The current 1.2.1 release ZIP predates these optional settings, which are available in the current source build.

---

## Why does Cmd+Tab switch to an app without bringing back its window?

| Shortcut | What happens | Does Cmd+Tab bring it back? |
|---|---|---|
| `Cmd+H` | Hides the app | Yes |
| `Cmd+M` | Minimizes the window to the Dock | **No** |
| `Cmd+W` | Closes the window | **No** |

Cmd+Tab switches apps. Minimized windows may stay in the Dock and closed windows stay closed.

When an app has no visible windows, Command Reopen asks macOS to reopen one. The app decides how it responds.

## Editions

| Edition | Mac App Store | Direct (GitHub) |
| :--- | :--- | :--- |
| **Download** | [Download on the Mac App Store](https://apps.apple.com/app/apple-store/id6757333924?pt=128417926&ct=readme&mt=8) | [Latest Release](https://github.com/Feng6611/mac-command-reopen/releases/latest) |
| **Window Restore Method** | macOS requests the app to reopen windows | New version can restore minimized windows with AX. Falls back to system reopening if disabled or restore fails. |
| **Permissions** | No Accessibility permission required | Required only when Advanced Window Restore is enabled |
| **Updates** | Automatic via App Store | Manual download |

## Features

- Restore minimized windows from the Dock when switching via Cmd+Tab.
- Reopen a default window for apps that closed their last window.
- Require zero permissions for core operations, using standard system workspace APIs.
- Return focus to the previous application when closing or minimizing the last window.
- Preserve standard macOS Cmd+Tab switcher UI and muscle memory completely intact.
- Exclude specific applications by name or bundle identifier in Settings.
- Run quietly from the menu bar, with an option to hide the status bar icon.

## FAQ

**Why doesn't Cmd+Tab restore minimized windows on macOS?**

macOS treats minimized windows as intentionally set aside. Cmd+Tab activates the application but leaves the window in the Dock. The built-in workaround — Cmd+Tab, hold Option, release Cmd — restores only one window at a time.

**Does Command Reopen need any permissions?**

Core window reopening requires no Accessibility or Screen Recording permission. It observes application activation using `NSWorkspace.didActivateApplicationNotification`, checks the public CoreGraphics window list (`CGWindowListCopyWindowInfo`) for an existing visible window, and only if none exists sends a reopen request via `NSWorkspace.openApplication(at:configuration:)` — the same request macOS sends when clicking an app's Dock icon. You can inspect the implementation in [CmdReopen/Features/Reopen](CmdReopen/Features/Reopen).

**Does it alter the Cmd+Tab switcher UI?**

No. The native switcher appears and functions exactly as before. Command Reopen acts only after you select an app.

**Can it reopen closed windows, not just minimized ones?**

Yes, if the application supports standard macOS reopen behavior. When you switch to an application with no visible windows, Command Reopen requests a reopen event, prompting supporting apps to open a new window.

**Does every switch guarantee a window appears?**

No. Command Reopen requests a standard reopen event only when an app has no visible windows. How the application responds depends on its own handling of standard reopen events (the same as clicking its Dock icon).

**Can I disable it for specific apps?**

Yes. Add them to Excluded Apps in Settings, and they will keep standard macOS Cmd+Tab behavior.

## Privacy

Command Reopen keeps window handling and app-specific activity on your Mac. The Mac App Store version sends anonymous product analytics (no app names, window titles or personal data); the GitHub build sends none. See [PRIVACY.md](PRIVACY.md).

## About

Built by [chenfeng](https://github.com/Feng6611) — I make focused, permission-light Mac utilities and Obsidian plugins, including [Open in Terminal](https://github.com/Feng6611/Obsidian-open-in-Teminal) and [File Ignore](https://github.com/Feng6611/Obsidian-File-Ignore).
