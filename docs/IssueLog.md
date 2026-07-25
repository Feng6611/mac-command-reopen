# Issue Log

## I-001 — Onboarding icon appears at the end of Cmd+Tab

- Date: 2026-07-25
- Status: Fixed locally; runtime smoke pending

### Symptom

When onboarding is opened from Settings, Command Reopen can appear at the far
right of Cmd+Tab. After clicking Minimize, a fast Cmd+Tab press can also happen
before Finder becomes frontmost, leaving Command Reopen in the wrong slot.

### Cause

- Changing the running app from `.accessory` to `.regular` adds its switcher
  item, but programmatic activation does not guarantee an MRU reorder.
- The minimize action requested an activation hand-off and immediately
  miniaturized the window without waiting for `NSWorkspace` to confirm it.

### Resolution

- For the Debug-only Settings replay, write a one-shot request and launch a
  fresh foreground instance through LaunchServices before showing onboarding.
  Terminate the old process only after the new instance exists. This recreates
  the real first-launch process condition without adding a release restart path.
- Confirm the return target is frontmost before miniaturizing the tutorial
  window.
- Retry cooperative activation for up to three seconds and keep the tutorial
  available for retry if the hand-off is not confirmed.
- Start the initial Commerce refresh on the next main-actor turn without the
  previous fixed one-second delay; readiness remains the presentation gate.
- After the return target is confirmed frontmost, order the inactive onboarding
  window onscreen and use AppKit's native document-window minimization behavior.
  This preserves Cmd+Tab order while keeping the Dock animation visible and
  respects the system Reduce Motion setting.
- Keep the actual previous foreground app as the return target; Finder remains
  only a fallback.
- While onboarding is active, suppress Command Reopen's normal reopen engine
  for external apps, including already-queued delayed evaluations. The
  onboarding controller remains responsible for restoring only its own window,
  and normal reopen behavior resumes when onboarding closes or finishes.

### Manual acceptance

Open onboarding from Settings, click through to the exercise, and confirm:

1. Command Reopen is first while its onboarding window is frontmost.
2. Clicking Minimize leaves the previous target app first and Command Reopen
   second, without reopening a minimized window in the target app.
3. One immediate Cmd+Tab restores the onboarding window and advances the flow.
