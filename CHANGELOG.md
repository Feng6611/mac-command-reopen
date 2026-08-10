# Changelog

## 1.4.2 — 2026-08-09

- Removed product analytics and the PostHog dependency from all distributions.
- Updated the direct edition to use the Command Reopen bundle identifier and
  the same non-commercial feature surface as the App Store edition.
- Renamed the direct edition status to Community edition; it has no RevenueCat,
  trial, purchase, or upgrade flow.
- Added a win-back offer shown when the paywall is closed after the trial ended
  without a purchase: the lifetime unlock at 20% off, bought in place, with the
  free GitHub build as the alternative. The discount runs for two days from the
  first showing and can be reopened from Settings and About until it expires,
  after which it does not return. Withheld from anyone the app restored fewer
  than five windows for.
- The free build's About status now reads "Free — full-featured, nothing
  locked. Same app as the App Store version." It previously said "Community
  edition", which named the distribution channel and implied a cut-down build.
- Added a support card to the free build's About pane: the App Store version as
  the primary action, Star on GitHub and Follow on X beside it, and an "I
  already did" that removes the card for good.
- Added a line under the About contact rows: real feedback gets a personal
  reply, usually with a 40% discount code.
- Reworked the paywall's visual hierarchy: brand color is now limited to the
  purchase button and the selected plan card, and the sheet takes the height
  its content needs instead of hiding overflow under the buttons.

## 1.4.1 — 2026-08-06

- Extended the automatic free trial from two days to fourteen days. Existing
  trials retain their original start date and use the new duration.
- Fixed App Store analytics configuration that could silently drop product
  events when the release bundle lacked its PostHog project token. First-open
  and onboarding-start events now flush immediately.
- Added an App Store build gate that rejects archives without the configured
  analytics token and host.

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
