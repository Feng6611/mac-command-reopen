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

## D-003 — Make one offer when the user closes the paywall after their trial ended

- Date: 2026-08-09
- Status: Accepted

### Context

Closing the paywall on an expired trial is the only moment Command Reopen knows
for certain that a user decided not to pay, and the last one before they either
forget the app or delete it. With product analytics removed in 1.4.2, it is
also the only place the app can still learn *why* — nothing else is measured.

### Decision

Present `TrialExitOfferView` once per machine at that moment, offering three
routes in a deliberate order:

1. **Another 14 days**, the same length as the original trial. First because
   the user is already leaving and this costs them nothing; staying installed
   is what makes the other two possible later. A shorter "last chance" window
   would read as a haggle — the problem is that they never reached a decision,
   and the honest fix is the same run again.
2. **Feedback by email**, prefilled with the one question worth asking now. The
   app's only remaining signal. The card promises a discount code by reply.
3. **The free Community edition**, as a footer link. Honest to offer, but it
   must not outrank a route that could still end in a sale.

The offer is withheld unless `TrialReceipt` resolves — below five restores the
card has no argument, and a second free fortnight spent on someone who never
adopted the feature buys neither a sale nor a signal. It is withheld once shown
or once an extension was taken: a trial that can always be renewed is not a
trial, and a card that reappeared until the user took one of its deals is the
nag this feature exists to avoid. Declining is an answer.

The discount code is sent by human reply rather than redeemed in the app.
macOS has no in-app offer-code redemption sheet, so an automated flow would end
at "here is a code, go find the App Store's redeem screen" — worse than an
email that is already a conversation.

Trial extension is a Commerce Kit mechanism (`KikiAccessManager.extendTrial`),
which preserves the original `trialStartedAt`. Whether to offer one, to whom,
and on what terms is app policy and lives in `TrialExitOffer`. The card itself
is composed from `KikiPaywall` atoms rather than the paywall sheet: it sells
nothing and has no plans, so reusing the sheet would have meant a purchase
layout with the purchase removed.

### Verification

`TrialExitOfferTests` covers each condition that withholds the offer, the
extension length, and the prefilled feedback mail.
`KikiAccessManagerTests` covers extension arithmetic, the preserved start date,
and the policies that ignore it. A manual pass is still required for the
paywall-close-to-card transition, which crosses two sheets.
