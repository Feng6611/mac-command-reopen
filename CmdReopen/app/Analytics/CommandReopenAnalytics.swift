import Foundation

#if APPSTORE
import PostHog
#endif

/// The product-owned boundary between Command Reopen's behaviour and its
/// analytics transport. It deliberately accepts only schema-defined values,
/// never the app/window identity that a reopen operation handled.
@MainActor
final class CommandReopenAnalytics {
    enum EventName: String {
        case appFirstOpened = "app_first_opened"
        case onboarding = "onboarding_event"
        case reopenActiveDay = "reopen_active_day"
        case paywallViewed = "paywall_viewed"
        case paywallAction = "paywall_action"
        case purchaseFlowResult = "purchase_flow_result"
    }

    struct Event: Equatable {
        let name: EventName
        let properties: [String: AnalyticsValue]
    }

    enum AnalyticsValue: Equatable {
        case string(String)
        case integer(Int)
        case boolean(Bool)
        case strings([String])
    }

    protocol Transport: AnyObject {
        func capture(_ event: Event, distinctID: String)
    }

    static let shared = CommandReopenAnalytics()

    private enum StorageKey {
        static let installationID = AppDefaults.RawKey.analyticsInstallationID
        static let firstOpenDate = "cmdreopen.analytics.firstOpenDate.v1"
        static let didCaptureFirstOpen = "cmdreopen.analytics.didCaptureFirstOpen.v1"
        static let activeDayKeys = "cmdreopen.analytics.activeDayKeys.v1"
    }

    private let defaults: UserDefaults
    private let now: () -> Date
    private let calendar: Calendar
    private var transport: Transport?

    init(
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init,
        calendar: Calendar = .current,
        transport: Transport? = nil
    ) {
        self.defaults = defaults
        self.now = now
        self.calendar = calendar
        self.transport = transport
    }

    /// Configures only the App Store target. A missing project token is an
    /// intentional no-op so analytics can never block Command Reopen itself.
    func configureIfPossible() {
        guard transport == nil else { return }

#if APPSTORE
        guard let configuration = PostHogConfiguration.fromMainBundle else {
            return
        }
        transport = PostHogTransport(configuration: configuration)
#endif
    }

    var isConfigured: Bool {
        transport != nil
    }

    func captureFirstOpen(entitlementState: String) {
        guard transport != nil,
              !defaults.bool(forKey: StorageKey.didCaptureFirstOpen) else {
            return
        }

        let date = now()
        defaults.set(date, forKey: StorageKey.firstOpenDate)
        capture(
            .appFirstOpened,
            properties: [
                "initial_entitlement_state": .string(entitlementState),
                // Existing installations cannot be distinguished reliably from
                // a new install at the first analytics rollout.
                "first_open_kind": .string("analytics_rollout")
            ]
        )
        defaults.set(true, forKey: StorageKey.didCaptureFirstOpen)
    }

    func captureOnboarding(
        stage: String,
        sessionID: String,
        durationMilliseconds: Int? = nil,
        completionMethod: String? = nil,
        entitlementState: String
    ) {
        var properties: [String: AnalyticsValue] = [
            "stage": .string(stage),
            "onboarding_session_id": .string(sessionID)
        ]
        if let durationMilliseconds {
            properties["duration_ms"] = .integer(durationMilliseconds)
        }
        if let completionMethod {
            properties["completion_method"] = .string(completionMethod)
        }
        capture(.onboarding, properties: properties, entitlementState: entitlementState)
    }

    func captureReopenActiveDay(totalSuccessfulReopens: Int, entitlementState: String) {
        guard totalSuccessfulReopens > 0 else { return }

        let currentDate = now()
        let localDate = Self.localDateFormatter.string(from: currentDate)
        var activeDayKeys = defaults.stringArray(forKey: StorageKey.activeDayKeys) ?? []
        guard !activeDayKeys.contains(localDate) else { return }

        activeDayKeys.append(localDate)
        activeDayKeys.sort()
        let firstOpenDate = defaults.object(forKey: StorageKey.firstOpenDate) as? Date
        let daysSinceFirstOpen = firstOpenDate.map {
            max(0, calendar.dateComponents([.day], from: calendar.startOfDay(for: $0), to: calendar.startOfDay(for: currentDate)).day ?? 0)
        } ?? 0

        capture(
            .reopenActiveDay,
            properties: [
                "local_date": .string(localDate),
                "active_day_index": .integer(activeDayKeys.count),
                "days_since_first_open": .integer(daysSinceFirstOpen),
                "reopens_bucket": .string(Self.reopenBucket(for: totalSuccessfulReopens))
            ],
            entitlementState: entitlementState
        )
        defaults.set(activeDayKeys, forKey: StorageKey.activeDayKeys)
    }

    func capturePaywallViewed(
        sessionID: String,
        source: String,
        defaultPlan: String,
        availablePlans: [String],
        totalSuccessfulReopens: Int,
        entitlementState: String
    ) {
        capture(
            .paywallViewed,
            properties: [
                "paywall_session_id": .string(sessionID),
                "source": .string(source),
                "paywall_version": .string("v1"),
                "default_plan": .string(defaultPlan),
                "available_plans": .strings(availablePlans),
                "reopens_bucket": .string(Self.reopenBucket(for: totalSuccessfulReopens)),
                "days_since_first_open": .integer(daysSinceFirstOpen)
            ],
            entitlementState: entitlementState
        )
    }

    func capturePaywallAction(
        sessionID: String,
        action: String,
        plan: String? = nil,
        source: String,
        totalSuccessfulReopens: Int,
        entitlementState: String
    ) {
        var properties: [String: AnalyticsValue] = [
            "paywall_session_id": .string(sessionID),
            "action": .string(action),
            "source": .string(source),
            "paywall_version": .string("v1"),
            "reopens_bucket": .string(Self.reopenBucket(for: totalSuccessfulReopens))
        ]
        if let plan {
            properties["plan"] = .string(plan)
        }
        capture(.paywallAction, properties: properties, entitlementState: entitlementState)
    }

    func capturePurchaseResult(
        attemptID: String,
        paywallSessionID: String,
        result: String,
        plan: String,
        source: String,
        durationMilliseconds: Int,
        errorCode: String? = nil,
        entitlementState: String
    ) {
        var properties: [String: AnalyticsValue] = [
            "purchase_attempt_id": .string(attemptID),
            "paywall_session_id": .string(paywallSessionID),
            "result": .string(result),
            "plan": .string(plan),
            "source": .string(source),
            "paywall_version": .string("v1"),
            "duration_ms": .integer(durationMilliseconds)
        ]
        if let errorCode {
            properties["error_code"] = .string(errorCode)
        }
        capture(.purchaseFlowResult, properties: properties, entitlementState: entitlementState)
    }

    private func capture(
        _ name: EventName,
        properties: [String: AnalyticsValue],
        entitlementState: String = "unrestricted"
    ) {
        guard let transport else { return }

        var commonProperties: [String: AnalyticsValue] = [
            "app_id": .string("command_reopen"),
            "app_name": .string("Command Reopen"),
            "platform": .string("macos"),
            "app_version": .string(Self.bundleString(for: "CFBundleShortVersionString")),
            "build_number": .string(Self.bundleString(for: "CFBundleVersion")),
            "distribution_channel": .string("app_store"),
            "os_version": .string(Self.osVersion),
            "app_locale": .string(Locale.current.identifier),
            "analytics_schema_version": .integer(1),
            "entitlement_state": .string(entitlementState)
        ]
        commonProperties.merge(properties) { _, value in value }
        transport.capture(Event(name: name, properties: commonProperties), distinctID: installationID)
    }

    private var installationID: String {
        if let existing = defaults.string(forKey: StorageKey.installationID), !existing.isEmpty {
            return existing
        }
        let created = "command_reopen:\(UUID().uuidString.lowercased())"
        defaults.set(created, forKey: StorageKey.installationID)
        return created
    }

    private var daysSinceFirstOpen: Int {
        guard let firstOpenDate = defaults.object(forKey: StorageKey.firstOpenDate) as? Date else {
            return 0
        }
        return max(0, calendar.dateComponents([.day], from: calendar.startOfDay(for: firstOpenDate), to: calendar.startOfDay(for: now())).day ?? 0)
    }

    private static let localDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static func reopenBucket(for count: Int) -> String {
        switch count {
        case ..<1: "0"
        case 1...2: "1_2"
        case 3...9: "3_9"
        case 10...29: "10_29"
        default: "30_plus"
        }
    }

    private static func bundleString(for key: String) -> String {
        (Bundle.main.object(forInfoDictionaryKey: key) as? String) ?? "unknown"
    }

    private static var osVersion: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "macOS \(version.majorVersion).\(version.minorVersion)"
    }
}

#if APPSTORE
private struct PostHogConfiguration {
    let projectToken: String
    let host: String

    static var fromMainBundle: Self? {
        guard let token = (Bundle.main.object(forInfoDictionaryKey: "CmdReopenPostHogProjectToken") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !token.isEmpty,
              !token.hasPrefix("phc_your_") else {
            return nil
        }
        let host = ((Bundle.main.object(forInfoDictionaryKey: "CmdReopenPostHogHost") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
            ?? "https://us.i.posthog.com"
        return Self(projectToken: token, host: host)
    }
}

@MainActor
private final class PostHogTransport: CommandReopenAnalytics.Transport {
    private let sdk = PostHogSDK.shared

    init(configuration: PostHogConfiguration) {
        let config = PostHogConfig(projectToken: configuration.projectToken, host: configuration.host)
        // Keep the SDK's standard app, device, locale, network, and lifecycle
        // context. Product-owned events never include an app/window identity
        // or any free-form user text.
        config.preloadFeatureFlags = false
        config.sendFeatureFlagEvent = false
        config.setDefaultPersonProperties = false
        config.personProfiles = .never
        config.errorTrackingConfig.autoCapture = false
        sdk.setup(config)
    }

    func capture(_ event: CommandReopenAnalytics.Event, distinctID: String) {
        sdk.capture(
            event.name.rawValue,
            distinctId: distinctID,
            properties: event.properties.reduce(into: [String: Any]()) { result, entry in
                result[entry.key] = entry.value.postHogValue
            }
        )
    }

}

private extension CommandReopenAnalytics.AnalyticsValue {
    var postHogValue: Any {
        switch self {
        case .string(let value): value
        case .integer(let value): value
        case .boolean(let value): value
        case .strings(let value): value
        }
    }
}
#endif

extension AccessEntitlementState {
    var analyticsValue: String {
        switch self {
        case .unrestricted: "unrestricted"
        case .trial: "trial"
        case .expired: "expired"
        case .pro: "pro"
        }
    }
}
