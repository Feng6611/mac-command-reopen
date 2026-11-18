//
//  CommandReopenAnalytics.swift
//  CmdReopen
//
//  The event table lives in docs/Analytics.md. Both release channels use
//  the PostHog transport. Debug composes the Kit with `.none`.
//

import Foundation
import KikiAnalytics
import StoreKit
#if !DEBUG
import KikiPostHog
#endif

/// Why a paywall was opened. The raw value is the `source` property.
enum PaywallSource: String {
    case onboarding
    case settingsAbout = "settings_about"
    case statusBarUpgrade = "status_bar_upgrade"
    case trialExpired = "trial_expired"
    /// The expired route reached before the trial started: access reads as
    /// expired then, but nothing has ended.
    case trialNotStarted = "trial_not_started"
    case trialUsage = "trial_usage"
}

/// What made the route open the paywall. The raw value is the `trigger` property.
enum PaywallTrigger: String {
    case user
    case launch
    case stateChange = "state_change"
    case activation
    case usage
}

/// The paywall is opened through several routes that do not share a call
/// stack, so the route leaves its reason here for the sheet to pick up.
@MainActor
enum PaywallSourceRelay {
    private static var pending: (PaywallSource, PaywallTrigger)?

    static func set(_ source: PaywallSource, trigger: PaywallTrigger = .user) { pending = (source, trigger) }

    static func take() -> (source: PaywallSource, trigger: PaywallTrigger) {
        defer { pending = nil }
        return pending ?? (.settingsAbout, .user)
    }
}

/// How the trial came to start. Whoever is about to start it leaves the reason
/// here; the access model reads it when the trial actually begins.
@MainActor
enum TrialStartRelay {
    enum Trigger: String {
        case paywallButton = "paywall_button"
        case onboardingFinished = "onboarding_finished"
        case onboardingWindowClosed = "onboarding_window_closed"
        /// Started by the first real restore, when onboarding had not started it.
        case firstReopen = "first_reopen"
        case other
    }

    private static var pending: Trigger?

    static func set(_ trigger: Trigger?) { pending = trigger }

    /// The first fallback that asked to start the trial is the one that did.
    static func setIfUnset(_ trigger: Trigger) {
        if pending == nil { pending = trigger }
    }

    static func take() -> Trigger {
        defer { pending = nil }
        return pending ?? .other
    }
}

enum CommandReopenEvent: KikiAnalyticsEvent {
    enum OnboardingStep: String { case welcome, tryMinimize = "try_minimize", success, finish, paywall }
    enum OnboardingOutcome: String { case finished, closed }
    enum PaywallActionKind: String { case purchase, restore, startTrial = "start_trial", close }
    enum PurchaseOperation: String { case purchase, restore }
    enum PurchaseOutcome: String { case success, cancelled, pending, failed }
    enum PlanKind: String { case lifetime, winbackLifetime = "winback_lifetime" }
    enum ErrorCategory: String {
        case network, unavailable, notAllowed = "not_allowed", noActivePurchase = "no_active_purchase", other
    }
    enum WinbackAction: String { case purchase, freeBuild = "free_build", dismiss, reopened }
    enum Setting: String {
        case launchAtLogin = "launch_at_login", showMenuBarIcon = "show_menu_bar_icon"
        case returnFocus = "return_focus", language
    }
    enum ReviewKind: String { case custom, systemRequest = "system_request" }
    enum ReviewAction: String { case review, notNow = "not_now" }
    enum HintKind: String { case firstSuccess = "first_success", returnTip = "return_tip" }

    case onboardingStepViewed(session: KikiAnalyticsSessionID, step: OnboardingStep)
    case onboardingDemoSucceeded(durationMs: Int)
    case onboardingCompleted(
        session: KikiAnalyticsSessionID, outcome: OnboardingOutcome, lastStep: OnboardingStep,
        launchAtLogin: Bool, durationMs: Int, demoSucceeded: Bool
    )
    case trialStarted(trigger: TrialStartRelay.Trigger, durationDays: Int?, minutesSinceFirstOpen: Int)
    case trialEnded(activeDays: Int, valueBucketCount: Int, winbackEligible: Bool)
    case paywallViewed(session: KikiAnalyticsSessionID, source: PaywallSource, trigger: PaywallTrigger, pricesAvailable: Bool)
    case paywallAction(
        session: KikiAnalyticsSessionID, action: PaywallActionKind, plan: PlanKind?,
        msSinceView: Int?, pricesAvailable: Bool
    )
    case purchaseResult(
        session: KikiAnalyticsSessionID?, operation: PurchaseOperation, result: PurchaseOutcome,
        plan: PlanKind?, error: ErrorCategory?
    )
    case reopenOpportunity
    case reopenResult(WindowReopenExecutor.Result)
    case appQuit(installDay: Int)
    case winbackOfferShown(valueBucketCount: Int)
    case winbackOfferAction(action: WinbackAction, daysLeft: Int)
    case reopenToggled(enabled: Bool)
    case settingChanged(Setting, enabled: Bool)
    case languageChanged(SupportedLanguage)
    case excludedAppsChanged(count: Int)
    case reviewPromptShown(ReviewKind)
    case reviewPromptAction(ReviewAction)
    case reopenHintShown(HintKind)

    var name: String {
        switch self {
        case .onboardingStepViewed: "onboarding step viewed"
        case .onboardingDemoSucceeded: "onboarding demo succeeded"
        case .onboardingCompleted: "onboarding completed"
        case .trialStarted: "trial started"
        case .trialEnded: "trial ended"
        case .paywallViewed: "paywall viewed"
        case .paywallAction: "paywall action"
        case .purchaseResult: "purchase result"
        case .reopenOpportunity: "reopen opportunity"
        case .reopenResult: "reopen result"
        case .appQuit: "app quit"
        case .winbackOfferShown: "winback offer shown"
        case .winbackOfferAction: "winback offer action"
        case .reopenToggled: "reopen toggled"
        case .settingChanged, .languageChanged: "setting changed"
        case .excludedAppsChanged: "excluded apps changed"
        case .reviewPromptShown: "review prompt shown"
        case .reviewPromptAction: "review prompt action"
        case .reopenHintShown: "reopen hint shown"
        }
    }

    var properties: KikiAnalyticsProperties {
        switch self {
        case let .onboardingStepViewed(session, step):
            ["session_id": .sessionID(session), "step": .enum(step)]
        case let .onboardingDemoSucceeded(durationMs):
            ["duration_ms": .int(durationMs)]
        case let .onboardingCompleted(session, outcome, lastStep, launchAtLogin, durationMs, demoSucceeded):
            [
                "session_id": .sessionID(session), "outcome": .enum(outcome), "last_step": .enum(lastStep),
                "launch_at_login": .bool(launchAtLogin), "duration_ms": .int(durationMs),
                "demo_succeeded": .bool(demoSucceeded)
            ]
        case let .trialStarted(trigger, durationDays, minutes):
            Self.compact([
                "trigger": .enum(trigger), "trial_duration_days": durationDays.map { .int($0) },
                "minutes_since_first_open": .int(minutes)
            ])
        case let .trialEnded(activeDays, count, winback):
            ["active_days": .int(activeDays), "value_bucket": .bucket(count), "winback_eligible": .bool(winback)]
        case let .paywallViewed(session, source, trigger, pricesAvailable):
            [
                "session_id": .sessionID(session), "source": .enum(source), "trigger": .enum(trigger),
                "prices_available": .bool(pricesAvailable)
            ]
        case let .paywallAction(session, action, plan, msSinceView, pricesAvailable):
            Self.compact([
                "session_id": .sessionID(session), "action": .enum(action), "plan": plan.map { .enum($0) },
                "ms_since_view": msSinceView.map { .int($0) }, "prices_available": .bool(pricesAvailable)
            ])
        case let .purchaseResult(session, operation, result, plan, error):
            Self.compact([
                "session_id": session.map { .sessionID($0) }, "operation": .enum(operation), "result": .enum(result),
                "plan": plan.map { .enum($0) }, "error_category": error.map { .enum($0) }
            ])
        case .reopenOpportunity:
            [:]
        case let .reopenResult(result):
            ["result": .enum(result.outcome), "reason": .enum(result.reason),
             "duration_ms": .int(result.durationMs), "daily_attempt_index": .int(result.dailyAttemptIndex)]
        case let .appQuit(installDay):
            ["install_day": .int(installDay)]
        case let .winbackOfferShown(count):
            ["value_bucket": .bucket(count)]
        case let .winbackOfferAction(action, daysLeft):
            ["action": .enum(action), "days_left": .int(daysLeft)]
        case let .reopenToggled(enabled):
            ["enabled": .bool(enabled)]
        case let .settingChanged(setting, enabled):
            ["setting": .enum(setting), "enabled": .bool(enabled)]
        case let .languageChanged(language):
            ["setting": .enum(Setting.language), "language": .enum(language)]
        case let .excludedAppsChanged(count):
            ["count_bucket": .bucket(count)]
        case let .reviewPromptShown(kind):
            ["kind": .enum(kind)]
        case let .reviewPromptAction(action):
            ["action": .enum(action)]
        case let .reopenHintShown(kind):
            ["kind": .enum(kind)]
        }
    }

    var frequency: KikiAnalyticsFrequency {
        switch self {
        case .onboardingDemoSucceeded, .trialStarted, .trialEnded, .winbackOfferShown: .oncePerInstall
        case .onboardingCompleted(_, .finished, _, _, _, _): .oncePerInstall
        case let .paywallViewed(session, _, _, _): .oncePerSession(id: session.rawValue)
        case .reopenOpportunity: .oncePerLocalDay
        default: .always
        }
    }

    private static func compact(_ values: [String: KikiAnalyticsValue?]) -> KikiAnalyticsProperties {
        values.compactMapValues { $0 }
    }
}

enum EntitlementLabel: String {
    case notStarted = "not_started", trial, expired, pro, unrestricted

    /// A trial that has not started still restores windows, so the app treats
    /// it as a trial (I-007); analytics keeps it apart, so a new user's
    /// onboarding is not counted as trial use.
    static func resolve(_ state: AccessEntitlementState, trialNotStarted: Bool) -> EntitlementLabel {
        if trialNotStarted { return .notStarted }
        return switch state {
        case .trial: .trial
        case .expired: .expired
        case .pro: .pro
        case .unrestricted: .unrestricted
        }
    }
}

@MainActor
enum CommandReopenAnalytics {
    static func make(
        entitlementState: @escaping () -> AccessEntitlementState,
        trialNotStarted: @escaping () -> Bool = { false },
        defaults: UserDefaults = .standard
    ) -> KikiAnalytics {
#if DEBUG
        let transport = KikiAnalyticsTransportFactory.none
#else
        let transport = KikiAnalyticsTransportFactory.postHog(.fromInfoPlist())
#endif
#if APPSTORE
        let channel = KikiAnalyticsApp.Channel.appStore
#else
        let channel = KikiAnalyticsApp.Channel.direct
#endif
        return KikiAnalytics(
            app: KikiAnalyticsApp(id: "command_reopen", channel: channel, storagePrefix: "cmdreopen.analytics"),
            transport: transport,
            // Anyone who finished onboarding or started a trial before analytics existed.
            isExistingUser: {
                let defaults = UserDefaults.standard
                return defaults.bool(forKey: AppDefaults.RawKey.hasSeenOnboarding)
                    || defaults.object(forKey: AppDefaults.RawKey.trialStartDate) != nil
            },
            context: {
                let label = EntitlementLabel.resolve(entitlementState(), trialNotStarted: trialNotStarted())
                return contextProperties(entitlement: label, defaults: defaults, now: Date())
            }
        )
    }

    /// Trial and download age travel with every event, so a purchase or a
    /// paywall can be placed on the user's own timeline.
    static func contextProperties(
        entitlement: EntitlementLabel,
        defaults: UserDefaults,
        now: Date
    ) -> KikiAnalyticsProperties {
        var properties: KikiAnalyticsProperties = ["entitlement_state": .enum(entitlement)]
#if APPSTORE
        if let day = trialDay(defaults: defaults, now: now) {
            properties["trial_day"] = .int(day)
        }
        if let days = defaults.object(forKey: RevenueCatConfiguration.trialDurationDaysKey) as? Int, days > 0 {
            properties["trial_duration_days"] = .int(days)
        }
        if let downloaded = OriginalDownload.date(defaults: defaults) {
            properties["days_since_download"] = .int(wholeDays(from: downloaded, to: now))
        }
#endif
        return properties
    }

    /// Day 1 is the day the trial started; it keeps counting after the trial ends.
    static func trialDay(defaults: UserDefaults, now: Date) -> Int? {
        guard let start = defaults.object(forKey: AppDefaults.RawKey.trialStartDate) as? Date else { return nil }
        return wholeDays(from: start, to: now) + 1
    }

    static func wholeDays(from start: Date, to end: Date) -> Int {
        max(0, Int(end.timeIntervalSince(start) / 86_400))
    }

    static var shared: KikiAnalytics { AppComposition.shared.analytics }

    static func track(_ event: any KikiAnalyticsEvent) { shared.track(event) }

    /// Bucketed total used by the trial and win-back events.
    static var totalReopens: Int { AppComposition.shared.reopenStats.totalSuccessfulReopens }

    /// Whole 24-hour intervals since first open; distinct from the Kit's
    /// local-calendar-day field on once-per-day events.
    static var installDay: Int { wholeDays(from: shared.firstOpenDate, to: Date()) }

    static var minutesSinceFirstOpen: Int { max(0, Int(Date().timeIntervalSince(shared.firstOpenDate) / 60)) }
}

/// When this Apple Account first downloaded the app, from the App Store's
/// signed app transaction. Unlike the analytics first open, it survives a
/// reinstall or a new Mac, so returning customers are not counted as new.
enum OriginalDownload {
    static let defaultsKey = "cmdreopen.analytics.originalDownloadDate"

    static func date(defaults: UserDefaults) -> Date? {
        defaults.object(forKey: defaultsKey) as? Date
    }

    /// Reads the cached transaction once; only the App Store release build has one.
    static func resolveIfNeeded(defaults: UserDefaults = .standard) {
#if APPSTORE && !DEBUG
        guard date(defaults: defaults) == nil else { return }
        Task {
            guard case let .verified(transaction) = try? await AppTransaction.shared else { return }
            defaults.set(transaction.originalPurchaseDate, forKey: defaultsKey)
        }
#endif
    }
}
