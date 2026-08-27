<p align="center">
  <img src="docs/icon.svg" alt="Command Reopen" width="160">
</p>

<h1 align="center">Command Reopen</h1>

<p align="center">
  <strong>Fix Cmd+Tab for minimized and closed windows on macOS.</strong>
</p>

<p align="center">
  Cmd+Tab to an app with a minimized or closed window — and nothing happens. Command Reopen makes the native Cmd+Tab restore those windows, the way it should have always worked.
</p>

<p align="center">
  <a href="https://apps.apple.com/app/apple-store/id6757333924?pt=128417926&ct=readme&mt=8">
    <img src="https://tools.applemediaservices.com/api/badges/download-on-the-mac-app-store/black/en-us?size=250x83&amp;releaseDate=1742256000" alt="Download on the Mac App Store" height="54">
  </a>
</p>

<p align="center">
  <sub>Prefer a free build? Grab the DMG from <a href="https://github.com/Feng6611/mac-command-reopen/releases">GitHub Releases</a> · <a href="https://commandreopen.com">Landing</a> · <a href="README_CN.md">中文</a></sub>
</p>


## Features

- **Restore minimized and closed windows** with Cmd+Tab — if an app has no open windows, a new one is created automatically
- **Zero permissions for core reopen** — the main Cmd+Tab reopen behavior needs no Accessibility or Screen Recording permission
- **Native switcher preserved** — works invisibly behind the stock Cmd+Tab UI
- **Configurable exclude list** for apps you don't want restored
- **Lightweight** menu bar app, <2 MB, near-zero CPU
- **Open source** (MIT) and fully auditable

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

The core logic is ~300 lines in a single file: [ActivationMonitor.swift](CmdReopen/Features/Reopen/ActivationMonitor.swift).

## FAQ

**Why does Cmd+Tab not restore minimized windows?**

macOS treats minimized windows as intentionally "put away." Cmd+Tab switches the active application but does not restore minimized windows by design. The only native workaround is Cmd+Tab → hold Option → release Cmd, which restores only one window at a time — and most users don't know it exists.

**Does Command Reopen need any permissions?**

No special permissions for the core app behavior. It uses `NSWorkspace` APIs available to sandboxed apps and needs no Accessibility or Screen Recording permission for Cmd+Tab reopen.

The optional Direct-build Advanced Window Restore mode uses Accessibility to
raise a window or restore all minimized windows. It is off by default, shown
separately in Settings, and always falls back to native reopen when unavailable.
Dock-click window cycling has its own default-off switch inside Advanced Mode.

**Does it change the Cmd+Tab interface?**

No. The native Cmd+Tab switcher stays exactly the same. Command Reopen works invisibly behind it — you won't notice any visual difference.

**Can it reopen windows that were closed, not just minimized?**

Yes. If you Cmd+Tab to an app that has no open windows, Command Reopen will create a new window automatically.

## Privacy

Command Reopen keeps window handling and app-specific activity on your Mac and
does not collect or transmit product analytics. See [PRIVACY.md](PRIVACY.md).

## RevenueCat development configuration

The App Store target reads its public RevenueCat SDK key from the gitignored
`Config/LocalSecrets.xcconfig`; copy `Config/LocalSecrets.example.xcconfig` to
that path and replace the placeholder. Never place RevenueCat secret REST keys
or App Store Connect private keys in the app configuration.

Command Reopen does not use RevenueCat Test Store. Both App Store configurations
use the same Apple public SDK key (`appl_`): Debug is an Apple Development-signed
build whose StoreKit transactions are routed to Apple Sandbox, while Release is
the production MAS build. All App Store builds reject `test_` keys.

Build the Apple Sandbox app without disabling code signing:

```sh
xcodebuild -project CmdReopen.xcodeproj -scheme CmdReopen-MAS \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath build/AppleSandboxDerivedData build
```

The App Store build guard runs after the app is produced and verifies that the
final app embeds the configured public key under the production bundle ID. A
valid Apple Development certificate is required; an ad-hoc or unsigned build is
not an Apple Sandbox build.

Use `./script/build_and_run.sh --verify` for the normal local loop. It stops
other Command Reopen instances, builds Debug with signing enabled, validates the
final RevenueCat key/Bundle ID and signature, then launches the deterministic
Apple Sandbox product.

## About

Built by [chenfeng](https://github.com/Feng6611) — I make small,
permission-light Mac utilities. More: [Clipboard Drop](https://apps.apple.com/app/id6768068044) · [Obsidian plugins](https://github.com/Feng6611)

## License

[MIT](LICENSE)
