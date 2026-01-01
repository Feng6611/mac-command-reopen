# Design & Strategy Notes

## Purpose
- Single place to log architecture choices, behavioral heuristics, and why they changed.
- Update this file whenever activation handling, launch-at-login, or status bar UX is adjusted.

## Current Architecture & Behavior
- Accessory app with status bar-only surface; no primary window scene. A SwiftUI `Settings` scene exists only for optional configuration.
- `ActivationMonitor` observes `NSWorkspace.didActivateApplicationNotification` when the feature toggle is on and re-opens the newly frontmost app.
- Finder handling is delayed by 0.2s and suppressed when a Space change occurred within 1.5s or the desktop was just cleared (tracked for 2.0s) to avoid unintentional re-opens.
- Same-bundle reopen calls are debounced for 0.1s to avoid re-entrant reopen loops (e.g., menu-bar/agent apps bouncing focus with Dock).
- After issuing `openApplication`, the next immediate `didActivate` for the same bundle is ignored once (self-trigger suppression within ~0.3s) to prevent echo activations.
- Hard filter: activations for `com.apple.dock` are ignored to avoid Dock<>app ping-pong in edge cases.
- Mouse-driven activations are ignored to reduce accidental relaunches while clicking or dragging.
- Feature toggle persists to `UserDefaults` via `com.comtab.autoHelpEnabled`; observers start/stop when the toggle flips.
- Logging is centralized in `AppLogger.activation` for activation-related telemetry.

## Launch & Permissions
- Status bar menu exposes About/Quit plus Launch at Login; launch toggle is backed by `SMAppService` on macOS 13+ and is disabled on earlier systems.
- App relies on Accessibility privileges for window inspection; keep `Info.plist` capabilities accurate and communicate prompt expectations in PRs.

## Change Log
- Initial baseline captured to document activation heuristics (Finder delay and suppression windows), feature toggle persistence, and launch-at-login strategy.
- Removed SwiftUI `WindowGroup` to keep the app windowless; only a `Settings` scene remains for optional configuration.
