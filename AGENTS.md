# Repository Guidelines

## Project Structure & Module Organization
ComTab is a macOS SwiftUI app. Core sources live in `ComTab/`: the entry point `ComTabApp.swift`, persistence helpers in `Persistence.swift`, and system integrations (`AccessibilityManager.swift`, `ActivationMonitor.swift`, `WindowInspector.swift`). Views sit in `ComTab/UI/`, assets in `Assets.xcassets`, and Core Data models in `ComTab.xcdatamodeld`. Unit tests reside in `ComTabTests/`, UI automation in `ComTabUITests/`. Add new code beside related modules and introduce subfolders only when several files share a concern.

## Build, Test, and Development Commands
- `open ComTab.xcodeproj`: open the project in Xcode for iterative development.
- `xcodebuild -scheme ComTab -configuration Debug build`: compile a local debug build; add `-quiet` in CI scripts.
- `xcodebuild -scheme ComTab -destination 'platform=macOS' test`: execute unit and UI tests. Narrow scope with `-only-testing:ComTabTests` or `ComTabUITests`.
- `xcodebuild -scheme ComTab -configuration Release build CODE_SIGNING_ALLOWED=NO`: create an unsigned release build for review.

## Coding Style & Naming Conventions
Follow Swift API Design Guidelines: four-space indentation, same-line braces, and 120-character lines. Use `UpperCamelCase` for types, `lowerCamelCase` for members, and prefix test doubles with `Mock`. Organize files with `// MARK:` pragmas, and keep side effects inside service classes (e.g., accessibility managers) to preserve SwiftUI view purity.

## Testing Guidelines
Write unit tests in `ComTabTests/` mirroring the module under test (e.g., `AccessibilityManagerTests`). Name tests `test_WhenCondition_ExpectOutcome` to capture behavior. UI flows live in `ComTabUITests/` using XCTest UI APIs. Cover permission flows and persistence updates, add regression tests for bug fixes, and run the full `xcodebuild ... test` command before opening a pull request.

## Commit & Pull Request Guidelines
Use imperative, ≤72-character summaries (`Add accessibility monitor tests`) and keep changes scoped. Reference issues with `#id` when available. Pull requests should describe intent, list validation steps, and call out user-facing accessibility impacts. Attach screenshots for UI updates and note configuration or entitlement adjustments in the description.

## Accessibility & Permission Configuration
The app depends on macOS accessibility privileges. Keep relevant `Info.plist` capabilities current. Extend `AccessibilityManager` or `ActivationMonitor` instead of duplicating authorization checks, and document new prompts so QA can verify them.
