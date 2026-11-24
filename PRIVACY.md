# Privacy Policy

Last updated: November 18, 2026

This Privacy Policy applies to Command Reopen, a macOS menu bar app.

Command Reopen is designed to keep sensitive product data on your Mac. It does not sell personal data or use it for advertising or cross-app tracking.

## Information We Process

Command Reopen observes app activation events and window visibility on your Mac so it can decide when to reopen a window after you switch apps with Cmd+Tab.

This activity is processed locally on-device. The identity of other apps, their bundle IDs, window titles, URLs, activation history, and per-app reopen statistics are not transmitted to the developer.

The app also stores local settings such as:

- whether auto reopen is enabled
- your excluded app list
- local reopen statistics
- onboarding state
- trial fallback state used for App Store access control

This data stays on your device unless you delete the app or reset its local container.

## Analytics

Both the Mac App Store version and, from version 1.5.5, the free GitHub build
send anonymous product analytics to PostHog so the developer can see whether
onboarding, window restoring, the trial and the purchase flow work. The events
describe how the app itself is used, such as finishing onboarding, a day on
which it restored a window, opening the purchase sheet, changing a setting, or
the trial ending. Each event carries a random identifier generated on your Mac
when the app first runs, the app version, your macOS version and device model,
which version you use (Mac App Store or GitHub), and your access state (trial,
expired or Pro; always unrestricted in the GitHub build). Counts are sent as
ranges.

It never includes the names or bundle IDs of other apps, window titles, URLs,
your excluded app list, activation history, or anything you type. The identifier
is not linked to your name, Apple ID or email, location is not collected, and
nothing is used for advertising or cross-app tracking.

The GitHub build has no trial or purchase, so it sends no purchase events. A
GitHub build compiled from source without a PostHog project token, and every
Debug build, sends nothing.

RevenueCat sends purchase events, including lifetime purchases, renewals and
cancellations, to the same PostHog project under the installation identifier.
RevenueCat keeps its existing anonymous customer identifier for purchase
validation and restores. No name, email or Apple ID is supplied to PostHog.

## Purchases

If you use the Mac App Store version, purchases, trials, renewals, and restores are handled through Apple and RevenueCat.

Command Reopen may receive purchase status information needed to determine whether Pro access is active. Payment details are processed by Apple, not by the developer.

## Permissions

Command Reopen's core Cmd+Tab behavior does not require Accessibility, Screen
Recording, Contacts, Location, or other sensitive macOS permissions. The
optional Advanced Window Restore mode in the GitHub build asks for Accessibility only
when the user opens its Settings control and enables it; no permission is
needed for the standard native fallback.

## Third Parties

For Mac App Store billing and entitlement management, and for anonymous product analytics in both versions, Command Reopen relies on:

- Apple App Store / StoreKit
- RevenueCat
- PostHog (anonymous product analytics, both versions)

Those services operate under their own privacy terms.

## Children

Command Reopen is not directed to children and does not knowingly collect personal information from children.

## Changes

This Privacy Policy may be updated from time to time. The latest version will be published in this repository and in any linked app documentation.

## Contact

Questions about privacy can be sent to fchen6611@gmail.com.
