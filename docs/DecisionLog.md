# Decision Log

## D-010 — Expiry asks; declining the paywall is what starts the discount

- Date: 2026-09-15
- Status: Accepted; restores D-003's trigger and narrows D-008

D-008 replaced two behaviours that existed in 1.5.0: an expired trial stopped
opening the paywall and merely left access state visible in Settings, and the
win-back clock moved from the paywall's close to the user explicitly opening
the offer. Both were wrong for this product. The reasoning is worth recording
because the D-008 version reads as more restrained and is easy to re-derive.

**Expiry asks, it does not wait.** The nudge on a Cmd+Tab reopen is a
once-a-day event that exists precisely because the feature the user wanted has
stopped working. Resolving that into "mark the prompt handled" left the app
silent at the one moment the user is looking for an explanation and has not
yet learned there is something to buy. A trial that ends must say so where the
decision is made, so expiry opens Settings › About on the paywall again. Two
things still hold the line D-008 was protecting: the window only opens when
none is already showing, and a visible onboarding window suppresses it rather
than being covered.

**The clock starts on a decline, not on a look.** `winbackOfferFirstShownAt`
is what makes "48 hours" true. D-008's version left the banner eligible to
appear the moment a trial expired, before the user had declined anything — a
countdown for a clock that had not started, advertising a discount to someone
who may still have been about to pay full price. It also meant the banner's
first appearance could not be the paywall close, so the one moment the app
knows the user decided not to pay was the one moment nothing happened.

The offer is therefore resolved on paywall close, excluding a close that
followed a purchase, and `activeWinbackOffer` gates every banner on the clock
having started. `TrialExitOffer.resolve` itself is unchanged from 1.5.0 and the
two-day window, receipt threshold, and unlisted SKU all keep their meaning.

D-008's other decisions stand: app-owned composition, the router, one sheet at
a time, and caching the excluded-app catalog.

### Verification

`SettingsAndStatusBarPresentationTests` covers expiry opening Settings › About
on the paywall, and expiry leaving an already-open Settings window alone.
`TrialExitOfferTests` covers that a purchase resolves to no offer, that the
window runs from the first showing rather than the latest, and that it closes
after two days. A manual pass is still required for the paywall-close-to-card
transition, which crosses two sheets, and for the purchase itself.

## D-009 — The menu bar icon is a shortcut into Settings, not the only entrance

- Date: 2026-09-15
- Status: Accepted

### Context

Some users want Command Reopen running without a permanent menu bar presence.
Hiding the icon is the easy half. The hard half is what replaces it: the status
item is also the only way to reach Settings, so removing it without an
alternative strands anyone who later wants to change a setting or quit.

Three ways to get back were considered. A global hotkey adds a shortcut to
learn and a key to conflict with other apps. Terminal commands are not a
gesture a normal user has. Opening the app again is the one action the user
already performs, needs no explanation, and costs nothing to support.

### Decision

- **One setting, default on.** "Show Menu Bar Icon" in Settings › General.
  On is the shipped behavior, so nothing changes until the user asks for it.
- **Launching the app again is the way back in.** With the icon hidden, a
  deliberate launch — Finder, Spotlight, Launchpad, or opening the running
  copy — opens Settings. The helper text states this, so the rule is taught
  where the decision is made rather than discovered by trial.
- **A login-item launch never opens a window.** That is the whole point of
  hiding the icon, and an open window at every login would be worse than the
  icon ever was. Distinguishing the two is the load-bearing part of this
  feature; `keyAELaunchedAsLogInItem` in the launch Apple Event is the
  documented signal, and it is read before the first run loop turn because it
  does not survive past it.
- **Onboarding outranks the setting.** A first launch already has a foreground
  presentation; a second window competing for the same moment is noise. The
  icon rule applies from the second launch on.
- **Hiding is the user's own choice, and it stays hidden.** Nothing brings the
  icon back except the switch itself.

The status item is removed by releasing `KikiMenuBarController`, whose `deinit`
calls `removeStatusItem`. That keeps visibility to one piece of state instead
of a live `NSStatusItem` plus a flag that can disagree with it.

### Verification

`LaunchPresentationPolicyTests` pins all four launch situations: a login-item
launch opens nothing, a user launch opens Settings only when the icon is
hidden, onboarding keeps the first launch, and re-opening a running copy opens
Settings only when the icon is hidden and onboarding is not showing.
`MenuBarIconSettingsTests` covers the on-by-default value and persistence.

Runtime verification (2026-09-15, Direct Debug build, isolated bundle ID so the
installed app's preferences were untouched): with the icon hidden a launch
produced a layer-0 Settings window and no status item, and re-opening that
running process reopened Settings while the PID stayed the same; with the icon
visible the same launch and re-open produced no window, matching the behavior
before this change. Instrumented logging confirmed the `aevt`/`oapp` launch
event is present at did-finish-launching under a real LaunchServices launch and
that `lgit` reads false there.

A real login-item launch remains unverified: launchd could not be exercised in
this environment, so the `lgit` path is covered by the documented attribute and
the API contract rather than an observed login. See I-004.

## D-008 — App-owned composition and explicit presentation

- Date: 2026-09-06
- Status: Accepted; amended by D-010

`AppComposition` owns the application services. Existing shared accessors forward
to this graph. `ActivationMonitor` delegates pure decisions to `ReopenPolicy`
and execution to `WindowReopenExecutor`; its expired-access callback reaches
`AppRouter`. Access state remains visible in Settings
and the menu, where users can explicitly open commerce surfaces.

Settings intentionally omits the master Enable toggle and its Status section.
The excluded-application editor caches the installed catalog asynchronously and
updates running applications incrementally. One optional `SettingsSheet` owns
presentation. Replacements wait for native dismissal and revalidate eligibility;
purchase review follow-up also waits for dismissal.
The custom review introduction and existing eligibility policy remain intact.

D-010 restores two behaviours this entry had changed: expiry opens the paywall
rather than only marking the prompt handled, and closing the paywall starts the
win-back clock rather than leaving it to an explicit open.

Verification (2026-09-07): all 109 application unit tests passed; the registry's
eight-project verification matrix passed, including the existing app UI tests.
Kiki ran 100 Swift Testing cases plus its XCTest suites. MAS build, development
signature/configuration checks and process launch passed; Direct compiled.
The matrix uses each caller's configured package references, including pinned
remote versions. Interactive visual inspection remains unverified because the
computer-use connection timed out; no purchase transaction was performed.

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
- Status: Accepted; its paywall-close trigger restored by D-010 after D-008 dropped it

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

## D-006 — Direct-only Accessibility advanced restore replaces Apple Events

- Date: 2026-08-25
- Status: Accepted; supersedes the 2026-08-13 Apple Events experiment

### Context

Apple Events required target-specific scripting dictionaries, Automation
consent, and Mac App Store temporary exceptions. That produced an app allowlist
instead of a reliable window capability, while the product's primary path has
always required no permission.

### Decision

The App Store target compiles only the native `NSWorkspace` reopen path. The
Direct target exposes a separate Advanced tab, where the user explicitly grants
Accessibility and enables Advanced Window Restore. KikiAuthorization supplies
only the status row and permission helper; Command Reopen owns the persisted
mode, recovery policy, window behavior, and copy.

After the ordinary CoreGraphics visibility check finds no visible window, an
enabled Direct mode uses AX to unminimize, focus, make main, and raise a window.
Its optional Restore All setting applies that operation to every minimized
window. Any missing permission, AX failure, or unavailable target returns to
the same native reopen fallback.

Dock cycling is a separate, default-off setting under Advanced Mode. It is
deliberately narrower than generic mouse activation: a global
click must AX-hit an `AXDockItem`, resolve an app bundle URL, and then match that
same process's workspace activation within one second. At mouse-down, the
monitor snapshots the target's AX minimized states and whether it was already
frontmost. A background app with any visible window retains native Dock
activation and creates no AX intent. A frontmost app with a visible window
locks Minimize All; an all-minimized app locks Restore All. Execution refreshes
the AX window elements but never re-plans from state the Dock just changed. One
coordinator owns that short-lived PID-bound intent for both activation
suppression and exactly-once execution. There is no retained per-app cycle
state beyond the current click. The hit test consumes `NSEvent.cgEvent.location`, because AX expects
Quartz's top-left-relative screen coordinates rather than AppKit's flipped
global coordinates. Restore All and foreground Minimize All wait 150 ms. A
defensive 750 ms minimize delay remains only for a future policy that might
allow minimizing during background activation; the current planner never emits
that combination. The cycle reports success only when every eligible AX window
reaches the requested minimized state.
Eligibility means the window exposes a readable `kAXMinimized` attribute;
non-window panels without that capability are excluded from the cycle.
The minimize branch never calls `NSRunningApplication.activate`: the Dock has
already activated the target, and a second asynchronous activation can undo a
successful AX minimize. Restore All still activates before raising windows.

### Verification

Behavior tests cover opt-in policy, minimized-only focused candidates, the
independently persisted Dock setting, foreground/background Dock policy,
action timing, single-owner intent lifecycle, Dock-role filtering, and
click-to-activation PID correlation. Build
both distributions and inspect the MAS artifact's empty app entitlement plist;
manual Direct smoke still needs a real Accessibility grant and Dock click.

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
