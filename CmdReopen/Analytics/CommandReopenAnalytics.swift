//
//  CommandReopenAnalytics.swift
//  CmdReopen
//
//  The event table lives in docs/Analytics.md. Only the App Store build has a
//  transport; every other build composes the Kit with `.none`, so call sites
//  never branch on the distribution.
//

import Foundation
import KikiAnalytics
#if APPSTORE
import KikiPostHog
#endif

/// Why a paywall was opened. The raw value is the `source` property.
enum PaywallSource: String {
    case onboarding
    case settingsAbout = "settings_about"
    case statusBarUpgrade = "status_bar_upgrade"
    case trialExpired = "trial_expired"
    case trialUsage = "trial_usage"
}

/// The paywall is opened through several routes that do not share a call
/// stack, so the route leaves its reason here for the sheet to pick up.
@MainActor
enum PaywallSourceRelay {
    private static var pending: PaywallSource?

    static func set(_ source: PaywallSource) { pending = source }

    static func take() -> PaywallSource {
        defer { pending = nil }
        return pending ?? .settingsAbout
    }
}

enum CommandReopenEvent: KikiAnalyticsEvent {
    enum OnboardingStep: String { case welcome, tryMinimize = "try_minimize", success, finish }
    enum OnboardingOutcome: String { case finished, closed }
    enum PaywallActionKind: String { case purchase, restore, close }
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

    case onboardingStepViewed(session: KikiAnalyticsSessionID, step: OnboardingStep)
    case onboardingDemoSucceeded(durationMs: Int)
    case onboardingCompleted(outcome: OnboardingOutcome, lastStep: OnboardingStep, launchAtLogin: Bool)
    case trialEnded(activeDays: Int, valueBucketCount: Int, winbackEligible: Bool)
    case paywallAction(session: KikiAnalyticsSessionID, action: PaywallActionKind, plan: PlanKind?)
    case purchaseResult(session: KikiAnalyticsSessionID, result: PurchaseOutcome, plan: PlanKind?, error: ErrorCategory?)
    case winbackOfferShown(valueBucketCount: Int)
    case winbackOfferAction(action: WinbackAction, daysLeft: Int)
    case reopenToggled(enabled: Bool)
    case settingChanged(Setting, enabled: Bool)
    case languageChanged(SupportedLanguage)
    case excludedAppsChanged(count: Int)
    case reviewPromptShown(ReviewKind)
    case reviewPromptAction(ReviewAction)

    var name: String {
        switch self {
        case .onboardingStepViewed: "onboarding step viewed"
        case .onboardingDemoSucceeded: "onboarding demo succeeded"
        case .onboardingCompleted: "onboarding completed"
        case .trialEnded: "trial ended"
        case .paywallAction: "paywall action"
        case .purchaseResult: "purchase result"
        case .winbackOfferShown: "winback offer shown"
        case .winbackOfferAction: "winback offer action"
        case .reopenToggled: "reopen toggled"
        case .settingChanged, .languageChanged: "setting changed"
        case .excludedAppsChanged: "excluded apps changed"
        case .reviewPromptShown: "review prompt shown"
        case .reviewPromptAction: "review prompt action"
        }
    }

    var properties: KikiAnalyticsProperties {
        switch self {
        case let .onboardingStepViewed(session, step):
            ["session_id": .sessionID(session), "step": .enum(step)]
        case let .onboardingDemoSucceeded(durationMs):
            ["duration_ms": .int(durationMs)]
        case let .onboardingCompleted(outcome, lastStep, launchAtLogin):
            ["outcome": .enum(outcome), "last_step": .enum(lastStep), "launch_at_login": .bool(launchAtLogin)]
        case let .trialEnded(activeDays, count, winback):
            ["active_days": .int(activeDays), "value_bucket": .bucket(count), "winback_eligible": .bool(winback)]
        case let .paywallAction(session, action, plan):
            Self.compact(["session_id": .sessionID(session), "action": .enum(action), "plan": plan.map { .enum($0) }])
        case let .purchaseResult(session, result, plan, error):
            Self.compact([
                "session_id": .sessionID(session), "result": .enum(result),
                "plan": plan.map { .enum($0) }, "error_category": error.map { .enum($0) }
            ])
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
        }
    }

    var frequency: KikiAnalyticsFrequency {
        switch self {
        case .onboardingDemoSucceeded, .trialEnded, .winbackOfferShown: .oncePerInstall
        case .onboardingCompleted(.finished, _, _): .oncePerInstall
        default: .always
        }
    }

    private static func compact(_ values: [String: KikiAnalyticsValue?]) -> KikiAnalyticsProperties {
        values.compactMapValues { $0 }
    }
}

private enum EntitlementLabel: String { case trial, expired, pro, unrestricted }

@MainActor
enum CommandReopenAnalytics {
    static func make(entitlementState: @escaping () -> AccessEntitlementState) -> KikiAnalytics {
#if APPSTORE
#if DEBUG
        let transport = KikiAnalyticsTransportFactory.none
#else
        let transport = KikiAnalyticsTransportFactory.postHog(.fromInfoPlist())
#endif
        let channel = KikiAnalyticsApp.Channel.appStore
#else
        let transport = KikiAnalyticsTransportFactory.none
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
                let label: EntitlementLabel = switch entitlementState() {
                case .trial: .trial
                case .expired: .expired
                case .pro: .pro
                case .unrestricted: .unrestricted
                }
                return ["entitlement_state": .enum(label)]
            }
        )
    }

    static var shared: KikiAnalytics { AppComposition.shared.analytics }

    static func track(_ event: any KikiAnalyticsEvent) { shared.track(event) }

    /// Bucketed total used by the trial and win-back events.
    static var totalReopens: Int { AppComposition.shared.reopenStats.totalSuccessfulReopens }
}
