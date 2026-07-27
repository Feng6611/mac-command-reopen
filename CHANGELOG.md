# Changelog

## 2026-07-27

- Added Simplified Chinese (`zh-Hans`) as a fourth translation and a new
  "简体中文" option in Settings › Language.
- Fixed copy that could never be translated. The Stats pane passed plain
  `String` literals to `SectionHeader` / `MetricTile` / `EmptyStateView`, so
  "Trend", "Top Apps", and both empty states rendered in English in every
  locale even though translations existed; "Today", "Active", "All time", the
  three range subtitles, the Active tile's day unit, and the chart series
  labels had never been localizable at all.
- Fixed the menu bar Quit item, which used a `Quit Command Reopen` key the
  catalog does not define, and now builds Kiki's shared `Quit %@` string.
- Fixed `Statistics — %lld restored`: the interpolation became a formatted
  `String` in "argue from the user's own numbers on the paywall", so the
  generated key was `%@` and the translations stopped resolving on macOS 13.
- Localized the six onboarding flow-diagram labels and the About pane's Email
  row, none of which were in the catalog.
- Rewrote the purchase errors. They now name what the user can do and no
  longer expose the commerce vendor or a raw plan identifier, and they are
  translated.
- `Day` / `Week` / `Month` and the fallback trend chart's date labels now
  follow the language chosen in Settings instead of the system language.
- Removed fourteen catalog entries with no remaining caller, including the
  language-restart alert dropped in "switch app language without restart".
- Two presentation tests asserted English literals against the developer's
  system language; they now pin the locale or assert the product decision.

## 2026-07-21

- Helper-like background processes (apps nested inside another `.app`,
  `*.helper` bundle IDs, names ending in " Helper") no longer trigger
  reopens, are never recorded, and are scrubbed from existing stats by a
  one-time subtractive migration on launch.
- ~~Menu bar icon now plays a single gentle pulse for the first 10 successful
  reopens each day, with a new "Pulse Menu Bar Icon on Reopen" Settings
  toggle.~~ Reverted in "Refine onboarding, settings, and review prompts";
  neither the toggle nor the pulse ships.

## 2026-07-14

- Production builds now resolve `Kiki_mackit` `0.8.0` and
  `KikiCommerceKit` `0.1.0` from their public GitHub tags.
- Kept `KikiCommerceTesting` linked only to the test target so the app uses
  the same onboarding, authorization, settings, and paywall flow as the
  released kits without shipping test-only helpers.
