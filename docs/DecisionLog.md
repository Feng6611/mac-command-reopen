# Decision Log

## D-001 — Keep onboarding Cmd+Tab ordering in Command Reopen

- Date: 2026-07-25
- Status: Accepted

### Context

Command Reopen normally runs as an accessory app. Opening onboarding from
Settings needs a regular foreground process so the minimize-and-return exercise
can appear in Cmd+Tab. Promoting and activating the existing process can make
it frontmost without changing its most-recently-used position in the switcher.
There is no AppKit API for directly editing that order.

The exercise needs two product-specific guarantees:

1. Onboarding opened from Settings enters Cmd+Tab through a normal foreground
   application launch, instead of an accessory-to-regular policy change.
2. After the user clicks Minimize, the window is not miniaturized until the
   return target is confirmed frontmost. This leaves Command Reopen second,
   ready for one Cmd+Tab press.
3. While onboarding owns the Cmd+Tab exercise, the normal activation monitor
   does not reopen the return target or any other external app. Only the
   onboarding controller restores Command Reopen's tutorial window.

### Decision

Keep this process and ordering behavior in `OnboardingWindowController`.
The Debug-only Settings replay writes a one-shot launch request, opens a new
foreground app instance through LaunchServices, and terminates the old menu-bar
instance only after the new process is confirmed. The new process consumes the
request before launch finishes and presents onboarding after its initial
commerce refresh. Release builds do not contain this replay/restart branch;
real onboarding already begins during a fresh first launch.

Keep the actual previous foreground app as the hand-off target, with Finder
only as a fallback when that app is no longer eligible. Suppress external
automatic reopen evaluation for the lifetime of onboarding, including delayed
evaluations queued just before onboarding began. Restore the monitor when
onboarding closes or finishes without changing the persisted feature setting.

Continue using `KikiOnboardingCoordinator` for the reusable window, navigation,
and completion mechanics, with its existing window escape hatch for the product
exercise.

Do not add this sequence to `KikiActivation`: that component handles ordinary
temporary promotion and restoration, not a tutorial whose success depends on
Cmd+Tab most-recently-used ordering and window miniaturization.

### Verification

Unit tests cover the one-shot Debug process hand-off request, onboarding window
session, and non-persisted activation-monitor suppression. A real Cmd+Tab smoke
test is still required because macOS owns the switcher ordering.

## D-002 — Start the trial independently of onboarding completion

- Date: 2026-07-26
- Status: Accepted

Command Reopen uses Kiki Commerce's automatic time trial, which writes the
trial start time when the app's access manager is first created. Onboarding
must not start, extend, or otherwise gate that trial.

The final onboarding step is therefore a product completion screen that calls
the onboarding coordinator's `finish` action directly. It neither presents a
paywall nor reaches into the access model. Paywalls remain available from their
normal post-onboarding routes after the trial expires or when a user opens them
explicitly.

This separation makes onboarding completion reliable even though trial access
was already granted during app launch.

## D-003 — One discounted way back when the trial ends without a purchase

- Date: 2026-08-10
- Status: Accepted

### Context

Closing the paywall on an expired trial is the only moment Command Reopen
knows for certain that a user decided not to pay, and the last one before they
either forget the app or delete it. With product analytics removed in 1.4.2,
the app cannot measure what happens next, so whatever it does here has to be
worth doing without a dashboard to confirm it.

An earlier draft of this card offered a second free trial period alongside a
free-build link. That was wrong: the Community build is permanently free and
functionally identical, so "another 14 days" is strictly worse than the option
sitting one line below it. Anyone who wants to keep using the app for nothing
already has a better answer than a second countdown.

### Decision

Offer one thing the free build cannot match — a lower price on the App Store
version — and keep the free build as the honest alternative rather than a
competitor to the offer.

- **A discounted SKU, not a code.** `com.dev.kkuk.CommandReopen.lifetime20`
  grants the same entitlement as the full-price lifetime unlock at 20% less,
  and the card buys it in place. macOS has no in-app redemption sheet, so a
  code would send someone who is already leaving to hunt for the App Store's
  redeem screen.
- **The SKU is configured but not listed.** It lives in
  `RevenueCatConfiguration.accessConfiguration` so `purchase(planID:)` can
  sell it, and is excluded from `visiblePaywallPlanIDs` so it never appears
  beside the full price, where it would tell every buyer they are paying too
  much.
- **Two days, from first showing.** `winbackOfferFirstShownAt` starts the
  clock once and is never rewritten, so reopening the card from a banner does
  not extend the discount. When the window closes the offer is gone for good;
  a discount that quietly returned would teach users that the listed price is
  never real.
- **Two ways back in while the window holds:** a row in Settings › General and
  one in About, each showing the days left. Not the menu bar — that surface is
  opened dozens of times a day, and a promotion there outstays its welcome by
  the second glance.
- **The card is withheld** unless `TrialReceipt` resolves. It argues from the
  user's own figures, and a discount pitched at someone the app never helped
  is spam with a price on it.

Deeper rewards stay off this card and live in About, where feedback earns a
personal reply and usually a 40% code. That exchange is deliberately manual:
it needs a human to judge whether the feedback helped, and reading it is the
only signal the app still has.

### Verification

`TrialExitOfferTests` covers the withholding conditions, the window running
from first showing rather than latest, expiry, the day countdown, and that the
win-back SKU is configured but absent from the paywall's plan list. A manual
pass is still required for the paywall-close-to-card transition, which crosses
two sheets, and for the purchase itself in the sandbox.

## D-004 — The free build's status states the deal, not the channel

- Date: 2026-08-10
- Status: Accepted

The About status row for the non-App Store build was called "Direct", then
"Community edition". Both kept getting rewritten because both name the
distribution channel, while the row a user opens About to read answers a
different question: do I have to pay, and is anything held back?

The value is now "Free", with "Full-featured, nothing locked. Same app as the
App Store version." underneath. "Community edition" additionally implied a
cut-down build, which is false — the two targets ship the same features.

Channel names still belong where provenance is the actual question: the README,
the Releases page, and the landing page call it the GitHub build. Two
vocabularies, two contexts, and neither borrows from the other.

## D-005 — One support ask per app, and it names that app's scarcest currency

- Date: 2026-08-10
- Status: Accepted

Cat Lock and the Command Reopen free build both needed a place to ask for
support, and both had more than one thing they could ask for. Listing every
option flattens them: a paid purchase and a free follow rendered side by side
read as equally weighted, and the expensive one loses.

Each app therefore makes one primary ask, chosen by what that app is short of,
with the rest demoted to quiet links and an "I already did" that removes the
card permanently.

- **Cat Lock's primary is Command Reopen.** For a free app with no paid tier,
  "try the app I do sell" costs the user nothing, converts far better than a
  tip, and can end in a purchase and a review. Buy Me a Coffee survives as a
  quiet link — it is still Cat Lock's only money path, and the phrase is part
  of the app — but it is no longer the button.
- **The free Command Reopen build's primary is the App Store version.** It
  keeps the app's one money path intact, and the copy says plainly that the
  paid build unlocks nothing extra, which is both true and more persuasive
  than a feature claim would be.
- **The menu bar keeps the tip entry and gains nothing new.** Settings and
  About are opened deliberately; the menu bar is used. Cross-promoting a
  second product from a menu opened dozens of times a day is more intrusive
  than the quiet can already there.

Neither card is extracted into Kiki yet. The two are close in shape but not
identical, and the workspace rule is to prove a component in two real apps
before lifting it.
