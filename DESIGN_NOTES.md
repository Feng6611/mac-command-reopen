# Design & Strategy Notes

## Purpose
- Single place to log architecture choices, behavioral heuristics, and why they changed.
- Update this file whenever activation handling, launch-at-login, or status bar UX is adjusted.

## Current Architecture & Behavior
- Accessory app with status bar-only surface; no primary window scene. A SwiftUI `Settings` scene exists only for optional configuration.
- `ActivationMonitor` observes `NSWorkspace.didActivateApplicationNotification` when the feature toggle is on.
- Reopen is evaluated after a short delay (0.12s) and only runs when the activated app is still frontmost.
- Reopen is skipped if the activated app already has a visible on-screen window, reducing duplicate-window cases from third-party launchers.
- Reopen is also skipped for very recent app launches (within 0.9s) to avoid racing normal startup window creation.
- Finder is hard-filtered (`com.apple.finder`) and never triggers reopen.
- Hard filter: activations for `com.apple.dock` are ignored to avoid Dock<>app ping-pong in edge cases.
- Same-bundle reopen calls are debounced for 0.1s to avoid re-entrant reopen loops (e.g., menu-bar/agent apps bouncing focus with Dock).
- After issuing `openApplication`, the next immediate `didActivate` for the same bundle is ignored once (self-trigger suppression within ~0.3s) to prevent echo activations.
- Mouse-driven activations are ignored to reduce accidental relaunches while clicking or dragging.
- Feature toggle persists to `UserDefaults` via `com.comtab.autoHelpEnabled`; observers start/stop when the toggle flips.
- Logging is centralized in `AppLogger.activation` for activation-related telemetry.

## Launch & Permissions
- Status bar menu exposes About/Quit plus Launch at Login; launch toggle is backed by `SMAppService` on macOS 13+ and is gracefully disabled on earlier systems (macOS 12).
- App does NOT require Accessibility privileges.

## Change Log
- Initial baseline captured to document activation heuristics (Finder delay and suppression windows), feature toggle persistence, and launch-at-login strategy.
- Removed SwiftUI `WindowGroup` to keep the app windowless; only a `Settings` scene remains for optional configuration.
- Refined Finder suppression to edge-triggered desktop-empty detection and added app hide/terminate temporal signals to reduce
  false Finder re-opens caused by system fallback activation on empty desktop.
- Added a Stage Manager-like fallback signal (recent non-Finder activation handoff) and a one-shot Finder retry override so
  empty-desktop fallback activations are suppressed without permanently blocking intentional Finder open.
- Switched Finder strategy to a hard filter: Finder activations are ignored completely and never reopened.
- Simplified activation heuristics by removing unused Finder suppression chains and adding delayed window-presence checks
  to avoid double-window reopen behavior for some third-party launch paths.
