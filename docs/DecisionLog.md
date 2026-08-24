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

## D-006 — Probe app-owned Apple Event adapters without replacing native reopen

- Date: 2026-08-13
- Status: Experimental

### Context

The existing `NSWorkspace.openApplication` route can restore one minimized
window or create a closed window, but it cannot ask every compatible app to
deminiaturize all of its windows. Safari, Chrome, Terminal, Preview, and iTerm2
expose minimized-window properties in their AppleScript dictionaries.
Runtime MAS tests proved Safari, Chrome, Terminal, Preview, iTerm2, and Ghostty.
Arc declares a writable property but its handler fails; Xcode 26.3 declares a
writable property but times out even while enumerating windows; Finder and VS
Code do not expose the required primitive; and the installed Dia version cannot
validate Dia's newer focus-only scripting API.

App Sandbox is a separate boundary. Automation consent does not grant a
sandboxed app permission to send arbitrary Apple Events. The MAS experiment
therefore names only known bundle IDs with a temporary Apple Events exception;
Direct uses the ordinary Hardened Runtime Automation entitlement.

### Decision

Keep the adapter registry, per-app preference and authorization state,
permission-denial cache, and native fallback inside Command Reopen's reopen
feature. This is direct product behavior and recovery policy, not a repeated
Kiki app-shell mechanism.

Standard reopen remains enabled by default. The enhanced multi-window route is
off by default and appears in its own Settings tab. Enabling one app first asks
macOS for Automation consent for that running target; only an approved target
is persisted. A denied, failed, or not-running target stays disabled.

Attempt an adapter only after CoreGraphics reports no visible window. Count a
positive restore as the successful reopen. For no minimized windows,
unsupported/focus-only dictionaries, permission denial, or script failure,
preserve the existing native reopen path. Cache a permission denial for the
process lifetime so later activations do not aggressively retry it.

Do not describe the MAS route as universal: a local signed build can prove a
listed target works, while App Review acceptance of temporary exceptions
remains a separate release decision.

### Verification

Unit tests cover the allowlist, property-name adapters, fallback routing, and
denial cache. The MAS artifact must build with App Sandbox, have its final
entitlements inspected, and be probed independently from Direct.

The Apple Development-signed MAS Debug artifact was inspected with `codesign`
and contained App Sandbox, Automation, and named temporary exceptions for only
the proven adapters. Its runtime matrix is:

| App | MAS Sandbox result |
| --- | --- |
| Safari | Restored one minimized window (`miniaturized`) |
| Chrome | Restored one window; a second run restored two and returned `windowCount: 2` |
| Terminal | Restored one minimized window; two-window fixture creation was unreliable |
| Preview | Restored one minimized document window |
| Arc | Declares `minimized`, but the handler returned AppleScript `-10000`; focus/native fallback |
| iTerm2 3.6.6 | Restored one minimized window (`miniaturized`) |
| Ghostty 1.3.1 | Restored the minimized test window through `activate window`; Ghostty exposes no minimized property |
| Xcode 26.3 | Declares writable `miniaturized`, but host and MAS probes timed out (`-1712`); excluded from Settings and the MAS exception list |
| Finder | Exposes `collapsed`, not a Dock-minimized primitive; native fallback |
| VS Code | No scripting dictionary; native fallback |
| Dia 1.0.2 | No scripting dictionary in the installed version; focus/native fallback marker |

Each adapter event has a three-second timeout. Permission denial is cached by
bundle ID for the process lifetime. A Debug-only
`--probe-apple-event-window-restore <bundle-id>` launch argument prints the
result from the signed artifact and exits.

## D-007 — One custom review introduction, then StoreKit owns later displays

- Date: 2026-08-15
- Status: Accepted with App Review risk

### Context

Command Reopen already chooses intentional review moments from successful
product use, but StoreKit may suppress every request and exposes no completion
result. The product wants one branded introduction before later eligible
requests return to the system prompt.

Apple's App Review Guideline 5.6.1 says custom review prompts may be rejected.
This is therefore a deliberate submission risk, not a new Kiki default.

### Decision

- Keep the existing MAS-only eligibility, one-request-per-launch behavior,
  successful-reopen threshold, and rolling annual cap.
- On the first eligible request, persist only that the custom prompt was shown.
  Never record or infer that the user submitted a review.
- The custom prompt offers `Review on App Store` and `Not Now`. It does not ask
  for a star rating, filter users by sentiment, reward a review, or change
  access. The primary action opens the App Store's `action=write-review` URL.
- Later eligible requests call StoreKit directly; Apple decides whether to
  display its system prompt.
- Put the product-neutral window, layout, and visible action reporting in
  `KikiReview`. Keep timing, copy, storage keys, distribution policy, StoreKit,
  and the App Store URL in Command Reopen.

### Verification

Kiki package tests cover configuration and construction. Command Reopen tests
cover first-custom/later-system routing, persistence, product thresholds, the
per-launch guard, and the rolling annual cap. Release review notes must call
out the one-time custom prompt, and the team must be ready to remove it if App
Review rejects the flow.
