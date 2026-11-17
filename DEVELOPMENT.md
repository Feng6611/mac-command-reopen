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

## Trial and paywall

New installs get a 7-day trial that starts explicitly on onboarding's last step; 1.5.2 installs keep
2 days and installs that already had a trial before 1.5.2 keep 14 (decided once and stored by
`RevenueCatConfiguration.resolveTrialDuration`). A trial that has not started still restores windows,
and the first real restore outside onboarding starts it (I-007). Yearly is no longer
sold; it stays configured only so existing subscribers resolve to their plan.

The paywall opens only for these reasons:

1. **Finishing onboarding**, always: "Get Started" on the last step opens the paywall as a sheet over
   the onboarding window, unless the person already owns Pro (`OnboardingPaywallPolicy`); closing the
   sheet finishes onboarding. App Store build only.
2. **Heavy use during a trial**: once the trial is older than 3 days, the day's 10th successful reopen
   shows it, at most once per calendar day (`ReopenPolicy.shouldPresentTrialUsagePaywall`, fired from
   `ReopenStatsStore.onReopenRecorded` through `AppRouter.handleTrialUsage`). A 2-day trial never gets
   there; it applies to the 14-day trials of older installs.
3. **Trial ended**: `CommandAccessModel` raises `shouldOpenProSettings` once per session on the first
   authoritative expired result (never on a first launch, never for an owner). `AppLifecycleCoordinator`
   presents it after the first commerce refresh and never over onboarding.
4. **Cmd+Tab while expired**, at most once a day (`ReopenPolicy.shouldShowExpiredNudge`).
5. **The user asks**: menu bar item, Settings › About. Closing it after an expired trial may show the
   win-back card (`TrialExitOffer`).

A trial that is merely running never opens it by itself. These rules are covered by
`CommandAccessModelTests`, `TrialExitOfferTests`, `ReopenPolicyTests` and `OnboardingPaywallPolicyTests`.

## Analytics

Events are defined in `CmdReopen/Analytics/CommandReopenAnalytics.swift` and listed in
[docs/Analytics.md](docs/Analytics.md). Call `CommandReopenAnalytics.track(...)`; never import PostHog
outside that file. Only the App Store build has a transport. The project token goes in
`Config/LocalSecrets.xcconfig` as `KIKI_POSTHOG_PROJECT_TOKEN`; without it nothing is sent, and a
Release App Store build fails. Debug builds always use the no-op transport, even when a token
is configured. The existing PostHog project is `mac-app` (528691); websites use separate projects.

## Releasing

Run before tagging; tags have no `v` prefix. It is read-only and never tags or pushes.

```sh
scripts/pre_tag_check.sh 1.5.2
```
