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
