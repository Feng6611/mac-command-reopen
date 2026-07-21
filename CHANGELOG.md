# Changelog

## 2026-07-21

- Helper-like background processes (apps nested inside another `.app`,
  `*.helper` bundle IDs, names ending in " Helper") no longer trigger
  reopens, are never recorded, and are scrubbed from existing stats by a
  one-time subtractive migration on launch.
- Menu bar icon now plays a single gentle pulse for the first 10 successful
  reopens each day (one-shot 0.8 s scale + opacity breath, honors Reduce
  Motion). New Settings toggle "Pulse Menu Bar Icon on Reopen", on by
  default. Requires a Kiki_mackit build that includes
  `KikiMenuBarController.pulseButton()` — tag a new Kiki_mackit release
  before the next App Store submission.

## 2026-07-14

- Production builds now resolve `Kiki_mackit` `0.8.0` and
  `KikiCommerceKit` `0.1.0` from their public GitHub tags.
- Kept `KikiCommerceTesting` linked only to the test target so the app uses
  the same onboarding, authorization, settings, and paywall flow as the
  released kits without shipping test-only helpers.
