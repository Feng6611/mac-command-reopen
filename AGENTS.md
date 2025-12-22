# Repository Guidelines

## Project Structure & Module Organization
- **App entry**: `ComTab/ComTabApp.swift` bootstraps the SwiftUI app.
- **Services**: `AccessibilityManager.swift`, `ActivationMonitor.swift`, `WindowInspector.swift`, and logging helpers in `AppLogger.swift`.
- **UI**: SwiftUI views live in `ComTab/UI/`; assets in `Assets.xcassets`; Core Data model in `ComTab.xcdatamodeld` (currently unused).
- **Tests**: Unit tests in `ComTabTests/`; UI automation in `ComTabUITests/`.

## Design & Strategy Log
- **Single source**: Capture key design decisions and behavioral strategies in `DESIGN_NOTES.md`.
- **When to update**: Any changes to activation heuristics, permission prompts, launch-at-login behavior, or status bar UX should be recorded there.

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
- **Focus**: Cover permission flows and persistence updates; add regression tests for fixes.
- **Execution**: Run `xcodebuild ... test` (full suite) before PRs.

## Commit & Pull Request Guidelines
- **Commits**: Imperative, ≤72 chars (e.g., `Add accessibility monitor tests`); scope tightly; link issues with `#id`.
- **PRs**: State intent, validation steps (commands run), accessibility impacts; attach screenshots for UI changes; note config/entitlement updates.

## Accessibility & Configuration Tips
- **Permissions**: App relies on macOS accessibility privileges; keep `Info.plist` capabilities accurate.
- **Extensibility**: Extend `AccessibilityManager` or `ActivationMonitor` for new prompts instead of duplicating checks; document new prompts for QA.
