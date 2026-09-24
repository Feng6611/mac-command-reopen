# Development

## Code map

The application graph is owned by [AppComposition.swift](CmdReopen/app/AppComposition.swift).
[ActivationMonitor.swift](CmdReopen/Features/Reopen/ActivationMonitor.swift) coordinates activation and window observation,
[ReopenPolicy.swift](CmdReopen/Features/Reopen/ReopenPolicy.swift) holds pure decisions, and
[WindowReopenExecutor.swift](CmdReopen/Features/Reopen/WindowReopenExecutor.swift) executes restoration with native fallback.
Commerce routes belong to the app router, while review eligibility and presentation live in
[ReviewPromptPolicy.swift](CmdReopen/Features/Review/ReviewPromptPolicy.swift).

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
