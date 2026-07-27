# PostHog analytics — implementation record

- Status: App Store client integration is verified against the `mac-app` PostHog
  project. The RevenueCat webhook remains a separately authorized server deployment.
- Scope: the shared multi-app event contract, with Command Reopen as the first
  implementation. This document is the source of truth for the first release;
  it does not authorize changes to other apps or to production services.
- Updated: 2026-07-26

## Why this exists

Command Reopen is a menu-bar utility. Launches, settings views, and foreground
time do not show whether it helped someone. The product's value event is a
successful `NSWorkspace.openApplication` completion after the app has decided a
window needs reopening. `ActivationMonitor` records that success in
`ReopenStatsStore`; that is the only source for value and retention metrics.

The event design deliberately sends at most one value event per installation
per local calendar day. Detailed totals remain local. This gives a useful
retention signal without exporting every Cmd+Tab action or the identity of the
third-party apps a person uses.

## Product boundary and rollout shape

PostHog is an analytics transport, not a Kiki feature. Event names, what counts
as value, the paywall source, and privacy policy stay in each product app. The
first implementation should add a small, app-owned `CommandReopenAnalytics`
facade with an injectable no-op test implementation. Do not add PostHog to
Kiki Base or make it infer product events. Reconsider a shared package only
after at least three apps have implemented the same stable contract.

The first release is limited to the App Store target. The Direct target remains
untracked until it has its own reviewed disclosure and configuration. Every
event nevertheless includes `distribution_channel`, so future Direct support
is explicit rather than inferred.

## Common contract for every app

| Property | Command Reopen value | Rule |
| --- | --- | --- |
| `app_id` | `command_reopen` | Stable, unlocalized product slug; never use a display name as the key. |
| `app_name` | `Command Reopen` | Readable dashboard label only. |
| `platform` | `macos` | Fixed platform slug. |
| `app_version` / `build_number` | Bundle marketing version / build | Read from the release bundle. |
| `distribution_channel` | `app_store` | Do not imply this from a product ID. |
| `os_version` | `macOS <major.minor>` | Coarsen to the OS release; no hardware model or device ID. |
| `app_locale` | Current app locale | BCP-47 identifier. |
| `analytics_schema_version` | `1` | Increase only for an incompatible schema change. |
| `entitlement_state` | `trial`, `expired`, `pro`, or `unrestricted` | Snapshot at capture time. |
| `distinct_id` | `command_reopen:<installation UUID>` | Stable only for this installation and this product. |

Create the installation UUID once in the app container, never derive it from
Apple, hardware, an email address, or a bundle identifier. Do not attempt to
join people across apps without a real account system. The PostHog client must
use this value as its distinct ID; the RevenueCat integration must use exactly
the same value as its `app_user_id` before its first configuration.

`app_id` means the product that emitted the event. It must never describe the
third-party app Command Reopen restored.

## Command Reopen event schema

The client keeps six event names. Optional fields are omitted when unavailable;
they are never populated with raw error text or a sentinel such as `unknown`.

| Event | Trigger and de-duplication | Event-specific properties |
| --- | --- | --- |
| `app_first_opened` | Once after analytics is configured for a new installation. Existing installations receive it once at rollout and carry `first_open_kind = analytics_rollout`, not a false install claim. | `initial_entitlement_state`, `first_open_kind` (`fresh_install` only when proven, otherwise `analytics_rollout`) |
| `onboarding_event` | Each meaningful onboarding transition. | `stage` (`started`, `demo_started`, `demo_succeeded`, `completed`), `onboarding_session_id`, `duration_ms` on completion, `completion_method` (`local_trial`, `yearly_purchase`, `lifetime_purchase`, `restore`, `without_trial`) |
| `reopen_active_day` | First **real** successful reopen on a local date, after helper filtering. A persisted `(installation UUID, local date)` key prevents repeats after relaunch. | `local_date`, `active_day_index`, `days_since_first_open`, `reopens_bucket` (`0`, `1_2`, `3_9`, `10_29`, `30_plus`) |
| `paywall_viewed` | Once for each newly created paywall session, not every SwiftUI appearance. | `paywall_session_id`, `source`, `paywall_version`, `default_plan`, `available_plans`, `reopens_bucket`, `days_since_first_open` |
| `paywall_action` | An explicit decision, before the corresponding flow begins. | `paywall_session_id`, `action` (`purchase`, `start_local_trial`, `restore`, `close`), `plan` for purchase, `source`, `paywall_version`, `reopens_bucket` |
| `purchase_flow_result` | Once for each purchase attempt after the Commerce result is authoritative. | `purchase_attempt_id`, `paywall_session_id`, `result` (`client_success`, `cancelled`, `failed`), `plan`, `source`, `paywall_version`, `duration_ms`, allowlisted `error_code` |

`client_success` means the local Commerce state became Pro. It is not the
revenue source of truth. `start_local_trial` represents Command Reopen's local
two-day entitlement and must not be represented as an App Store or RevenueCat
trial.

### Exact capture points in the current app

| Current owner | Capture point to add | Important constraint |
| --- | --- | --- |
| `CommandReopenAnalytics` | Configure PostHog only when the first product event is ready to send; it emits `app_first_opened` first when needed. | An idle menu-bar session does not create PostHog queues or periodic flush timers; a missing release token remains a safe no-op. |
| `OnboardingWindowController` and `OnboardingTryMinimizeModel` | `started` when a first-launch coordinator is presented; `demo_started` from the Minimize action; `demo_succeeded` only after the existing real Cmd+Tab return succeeds; `completed` from the coordinator completion. | The onboarding demo is not a real reopen and never emits `reopen_active_day`. |
| `ActivationMonitor.handleReopenCompletion` / `ReopenStatsStore` | Notify analytics only after `recordSuccessfulReopen` accepts the result. | The analytics API receives only a sanitized day, count bucket, and derived index. It never receives `bundleID`, `localizedName`, URL, or per-app counts. |
| `PaywallSheetView` and its callers | Allocate the session before presentation and capture the view once. Pass a product-owned source through all callers. | Current callers do not distinguish `settings`, `status_bar`, `onboarding`, `trial_expired_launch`, and `expired_reopen_nudge`; this propagation is required before capture. |
| Commerce paywall actions | Observe the shared manager's published purchase/restore state from `PaywallSheetView`, then emit app-owned action and result events. | Kiki keeps ownership of button mechanics; Command Reopen maps only the public plan, feedback, and error category to its product event schema. |

The expired nudge in `ActivationMonitor` maps to
`source = expired_reopen_nudge`. A normal upgrade prompt caused by commerce
refresh maps to `trial_expired_launch`; Settings, status-bar, and onboarding
must each preserve their own explicit source.

## RevenueCat transaction events

Revenue is captured server-side as one `revenuecat_event` name. A verified
RevenueCat webhook endpoint maps RevenueCat app/product identifiers to the
canonical `app_id`, rejects an invalid webhook authorization header, and
deduplicates by `rc_event_id` before forwarding to PostHog. The client never
holds the server ingestion key.

The first supported `rc_event_type` values are `initial_purchase`,
`non_renewing_purchase`, `renewal`, `cancellation`, `expiration`,
`billing_issue`, and `refund`. Required properties are `rc_event_id`,
`rc_event_type`, `product_id`, `plan`, `price`, `currency`, `country_code`,
`environment`, `offering_id`, `purchased_at`, `expiration_at`,
`transaction_id`, and `original_transaction_id` where RevenueCat supplies
them. Product and transaction identifiers are transaction data, not client
behaviour; they are not copied into client events.

For Command Reopen, the mapping begins with:

```text
RevenueCat app / Command Reopen product IDs
  -> command_reopen
```

The exact RevenueCat App ID and webhook endpoint are deployment configuration,
not source constants. Adding the Worker/webhook and configuring RevenueCat are
separate, user-authorized production changes; neither is part of this document
change.

## Prerequisites and release gates

1. Create or confirm the target PostHog project and region. Record the project
   name and host in release configuration, but do not commit any token.
2. Add the official `posthog-ios` package as an HTTPS exact release tag and
   regenerate `Package.resolved`; do not retain a local package reference in a
   release build.
3. Add `CMDREOPEN_POSTHOG_PROJECT_TOKEN` and `CMDREOPEN_POSTHOG_HOST` as build
   settings supplied by ignored local configuration and release CI. Surface them
   in `AppInfo.plist` only for the App Store target. The project token is
   intentionally usable by a client, but it is still not stored in this repo;
   a personal/server key must never enter the app bundle.
4. Extend the generic `KikiRevenueCat.RevenueCatConfiguration` with an optional
   app user ID and pass it at the initial RevenueCat configuration. This must
   happen before any purchase or restore, preserving the installation ID across
   launches. Add unit coverage in Kiki and Command Reopen before relying on
   client/webhook joins.
5. Update `PRIVACY.md`, the published privacy page, and
   `PrivacyInfo.xcprivacy` in the same release. The current policy says no data
   is collected for analytics and the manifest declares no collected data, so
   shipping telemetry before these changes would be inaccurate.
6. Implement and verify the RevenueCat webhook independently. Its PostHog
   server credential lives only in Worker/secret storage.

The PostHog SDK supports Swift Package Manager configuration and queues events
while offline. This release disables automatic lifecycle and screen events,
method swizzling, person profiles, feature flag event collection, and automatic
error capture. Its explicit product-event queue flushes no more often than once
per 15 minutes. Session replay, surveys, and identity-linking collection require
a separate reviewed decision. See the official [iOS SDK documentation](https://posthog.com/docs/libraries/ios)
and [privacy guidance](https://posthog.com/docs/privacy).

## Privacy contract

Allowed client data: product/version/locale, coarse OS version, anonymized
installation ID, entitlement state, daily value occurrence, usage bucket,
paywall context, plan, and allowlisted purchase outcome.

Never capture or send:

- a restored app's name, bundle ID, URL, window title, activation history, or
  per-app statistics;
- excluded-app settings, file paths, hardware identifiers, Apple account data,
  email addresses, IP-derived properties, or free-form errors;
- a project personal API key, RevenueCat secret, webhook authorization, or raw
  transaction payload in a client event.

The product is responsible for choosing lawful collection and disclosing it;
PostHog does not make that choice for the product.

## Verification before release

1. Unit-test the facade with a recording sink: common fields, installation ID,
   one `app_first_opened`, bucket boundaries, local-day de-duplication, and
   no capture on failed/helper reopen attempts.
2. Unit-test onboarding and each paywall source/action/result. Assert no raw
   app identifier, display name, URL, or error appears in captured properties.
3. Use a PostHog development project to inspect one event of every event name
   and verify the exact schema, distinct ID, and absence of forbidden data.
4. Run the App Store target's existing build/tests in isolated DerivedData, and
   perform a manual Cmd+Tab smoke: a true successful reopen produces one daily
   event; the onboarding demo produces none.
5. In RevenueCat sandbox, verify the same installation ID reaches the webhook,
   duplicate webhook delivery does not duplicate `revenuecat_event`, and client
   purchase success is not used as revenue truth.
6. Publish the updated privacy disclosure before enabling production capture.

## Initial dashboards

- **Portfolio Overview:** First Open, Activated Users, Weekly Benefited Users
  (WBU), paying users, revenue, and revenue per activated user; filter or
  break down by `app_id`.
- **Activation:** `app_first_opened -> onboarding_event.started ->
  onboarding_event.demo_succeeded -> onboarding_event.completed ->
  reopen_active_day`. "Activated" means at least two local active days and the
  local total in the `3_9` bucket or above within seven days.
- **Retention:** WBU, active days per week, and D1/D7/D30 value retention all
  based on `reopen_active_day`, never process launches.
- **Monetization:** `paywall_viewed -> paywall_action.purchase ->
  purchase_flow_result.client_success -> revenuecat_event`. Break down by
  source, plan, `paywall_version`, `reopens_bucket`, and days since first open.
  Interpret revenue and active paid access from the webhook, not the client.

Dashboard conclusions must keep numerator and denominator within the same
`app_id`; multi-app totals are a deliberate portfolio view, not a silent mix of
unrelated products.
