# Command Reopen

**Fix Cmd+Tab for minimized and closed windows on macOS.**

You press Cmd+Tab to switch to an app — nothing happens. The app shows as "active" in the switcher, but its window is still minimized in the Dock. Or worse, you closed the window earlier and now Cmd+Tab brings up the app with no window at all.

Command Reopen fixes this. It makes the native Cmd+Tab automatically restore minimized and closed windows — the way you always expected it to work.

<p align="center">
  <a href="https://commandreopen.com">🌐 Landing Page</a> &nbsp;•&nbsp;
  <a href="https://apps.apple.com/app/id6757333924?ct=cmdr_github_readme&mt=8">🛒 Mac App Store</a> &nbsp;•&nbsp;
  <a href="https://github.com/Feng6611/mac-command-reopen/releases">📦 Download</a> &nbsp;•&nbsp;
  <a href="README_CN.md">🇨🇳 中文</a>
</p>


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

Command Reopen listens for app activation events via `NSWorkspace.didActivateApplicationNotification`. When you Cmd+Tab to an app, it first checks whether that app already has a visible on-screen window by inspecting the public CoreGraphics window list (`CGWindowListCopyWindowInfo`). Only if no visible window is found does it send a restore request through `NSWorkspace.openApplication(at:configuration:)`. This brings back minimized windows and recreates closed ones — all using standard macOS APIs that require no special permissions.

The core logic is ~300 lines in a single file: [ActivationMonitor.swift](ComTab/ActivationMonitor.swift).

## Testing And Logs

For local verification, use the shared `ComTab` scheme. Its `Run` action now uses `Debug`, while `Profile` and `Archive` remain on release configurations.

If you want to verify the new visible-window check, run the app and watch the activation logs:

```bash
log stream --style compact --level debug --predicate 'subsystem == "com.dev.kkuk.CommandReopen.direct" OR subsystem == "com.dev.kkuk.CommandReopen" OR subsystem == "com.dev.kkuk.CmdReopen"'
```

The important lines look like this:

- `Application did finish launching. version=1.1.0 build=9`
- `Window inspection for com.apple.TextEdit: total=1, onScreen=1, visibleCandidates=1, transparent=0, tiny=0, hasVisibleWindow=true`
- `Skipping reopen for com.apple.TextEdit; app already has a visible window.`
- `Re-opening com.apple.TextEdit`

Suggested manual checks:

1. Open an app with a normal visible window, then Cmd+Tab back to it. You should see `hasVisibleWindow=true` and no `Re-opening ...`.
2. Minimize the app window, then Cmd+Tab back. You should see `hasVisibleWindow=false` followed by `Re-opening ...`.
3. Close all windows for an app that supports opening a fresh one, then Cmd+Tab back. You should again see `hasVisibleWindow=false` followed by `Re-opening ...`.
4. Try an app with tiny transient panels or overlays. The log includes `tiny=` so you can confirm whether a small window was intentionally ignored by the heuristic.

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
