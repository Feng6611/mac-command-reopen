# Repository Guidelines

## Project Structure & Module Organization
- **App entry**: `ComTab/ComTabApp.swift` bootstraps the SwiftUI app.
- **Core services**: `ActivationMonitor.swift`, `LaunchAtLoginManager.swift`, `StatusBarController.swift`, and logging helpers in `AppLogger.swift`.
- **App lifecycle**: `AppDelegate.swift` manages app-level startup behavior for the menu-bar app.
- **Assets**: app icons/colors are under `ComTab/Assets.xcassets`.
- **Tests**: Unit tests in `ComTabTests/`; UI automation in `ComTabUITests/`.

## Design & Strategy Log
- **Single source**: Capture key design decisions and behavioral strategies in `DESIGN_NOTES.md`.
- **When to update**: Any changes to activation heuristics, permission prompts, launch-at-login behavior, or status bar UX should be recorded there.

## Activation Behavior Guardrails
- **System app filters**: Never trigger reopen for Finder (`com.apple.finder`) or Dock (`com.apple.dock`).
- **Reopen timing**: Evaluate reopen after a short delay, and only if the same app is still frontmost.
- **Visible-window check**: Skip reopen when the app already has a visible on-screen window to avoid duplicate windows.
- **Launch race suppression**: Skip reopen for very recent launches to avoid racing normal startup window creation paths.
- **Loop prevention**: Keep same-bundle reopen debounce and self-trigger suppression to avoid echo activations.

## Build, Test, and Development Commands
- **Open in Xcode**: `open ComTab.xcodeproj` for iterative dev.
- **Debug build**: `xcodebuild -scheme ComTab -configuration Debug build` (add `-quiet` in CI).
- **Release (unsigned)**: `xcodebuild -scheme ComTab -configuration Release build CODE_SIGNING_ALLOWED=NO`.
- **Tests**: `xcodebuild -scheme ComTab -destination 'platform=macOS' test`; scope with `-only-testing:ComTabTests` or `ComTabUITests`.

## Coding Style & Naming Conventions
- **Swift style**: Four-space indentation, same-line braces, 120-char lines.
- **Naming**: UpperCamelCase types; lowerCamelCase members; prefix test doubles with `Mock`.
- **Organization**: Use `// MARK:` pragmas; keep side effects in service classes to keep views pure.

## Testing Guidelines
- **Frameworks**: XCTest for unit and UI tests.
- **Naming**: `test_WhenCondition_ExpectOutcome`.
- **Focus**: Cover activation reopen heuristics, launch-at-login persistence, and regressions (especially duplicate-window cases).
- **Execution**: Run `xcodebuild ... test` (full suite) before PRs.

## Commit & Pull Request Guidelines
- **Commits**: Imperative, ≤72 chars (e.g., `Add accessibility monitor tests`); scope tightly; link issues with `#id`.
- **PRs**: State intent, validation steps (commands run), accessibility impacts; attach screenshots for UI changes; note config/entitlement updates.

## Accessibility & Configuration Tips
- **Permissions**: App does NOT require any special system permissions (e.g. Accessibility). It uses standard APIs like `NSWorkspace` and `CGWindowList`.
- **Extensibility**: Extend `ActivationMonitor` for new heuristics.
