# Changelog

## 2026-07-14

- Production builds now resolve `Kiki_mackit` `0.8.0` and
  `KikiCommerceKit` `0.1.0` from their public GitHub tags.
- Kept `KikiCommerceTesting` linked only to the test target so the app uses
  the same onboarding, authorization, settings, and paywall flow as the
  released kits without shipping test-only helpers.
