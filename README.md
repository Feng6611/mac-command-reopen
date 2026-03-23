# Command Reopen

**Fix Cmd+Tab for minimized and closed windows on macOS.**

You press Cmd+Tab to switch to an app — nothing happens. The app shows as "active" in the switcher, but its window is still minimized in the Dock. Or worse, you closed the window earlier and now Cmd+Tab brings up the app with no window at all.

Command Reopen fixes this. It makes the native Cmd+Tab automatically restore minimized and closed windows — the way you always expected it to work.

📹 [Watch Demo](https://commandreopen.com/demo.mp4) &nbsp;|&nbsp; [中文介绍](README_CN.md)

## Install

### Mac App Store

**[Download on the Mac App Store](macappstore://apps.apple.com/app/id6757333924)**

### Download Binary

**[Download Latest Release](https://github.com/Feng6611/mac-command-reopen/releases)**

### Build from Source

```bash
git clone https://github.com/Feng6611/mac-command-reopen.git
cd mac-command-reopen
open ComTab.xcodeproj
# Select the "ComTab" scheme → Build & Run (⌘R)
# Requires Xcode 15+ and macOS 12.0+
```

## Features

- Restore minimized windows with Cmd+Tab
- Restore closed windows with Cmd+Tab — if an app has no open windows, a new one is created automatically
- No system permissions required — no Accessibility, no Screen Recording, nothing
- Does not replace the native Cmd+Tab interface — works invisibly behind it
- Smart activation tracking — skips unnecessary restores when rapidly switching
- User-configurable exclude list for specific apps
- Launch at Login support (macOS 13+)
- Lightweight menu bar app (<2 MB, near-zero CPU usage)
- Open source and fully auditable

## macOS Window Shortcuts You Should Know

| Shortcut | Action |
|---|---|
| `Cmd+Tab` | Switch between apps |
| `` Cmd+` `` | Switch windows within the same app |
| `Cmd+H` | Hide current app (Cmd+Tab brings it back) |
| `Cmd+M` | Minimize current window to Dock |
| `Cmd+W` | Close current window |
| `Cmd+Option+H` | Hide all other apps |
| `Cmd+Tab` → hold `Option` → release `Cmd` | Restore one minimized window (native workaround) |

Notice the gap? **Cmd+H** (Hide) works perfectly with Cmd+Tab — the window comes right back. But **Cmd+M** (Minimize) and **Cmd+W** (Close) don't — Cmd+Tab switches to the app but the window stays gone.

That's exactly what Command Reopen fixes. Every Cmd+Tab switch restores your windows automatically.

## How It Works

Command Reopen listens for app activation events via `NSWorkspace.didActivateApplicationNotification`. When you Cmd+Tab to an app, it detects the switch and sends a restore request through `NSWorkspace.openApplication(at:configuration:)`. This brings back minimized windows and recreates closed ones — all using standard macOS APIs that require no special permissions.

The core logic is ~300 lines in a single file: [ActivationMonitor.swift](ComTab/ActivationMonitor.swift).

## FAQ

**Why does Cmd+Tab not restore minimized windows?**

macOS treats minimized windows as intentionally "put away." Cmd+Tab switches the active application but does not restore minimized windows by design. The only native workaround is Cmd+Tab → hold Option → release Cmd, which restores only one window at a time — and most users don't know it exists.

**Does Command Reopen need any permissions?**

No. It uses `NSWorkspace` APIs available to sandboxed apps. No Accessibility permission, no Screen Recording, no special entitlements.

**Does it change the Cmd+Tab interface?**

No. The native Cmd+Tab switcher stays exactly the same. Command Reopen works invisibly behind it — you won't notice any visual difference.

**Can it reopen windows that were closed, not just minimized?**

Yes. If you Cmd+Tab to an app that has no open windows, Command Reopen will create a new window automatically.

## Privacy

Command Reopen collects no data. Everything runs locally on your Mac. See [PRIVACY.md](PRIVACY.md).

## License

[MIT](LICENSE)
