import Foundation

@MainActor
final class AppRouter {
    private let accessController: AppAccessController
    private let prepare: (SettingsTab?, Bool) -> Void
    private let open: (SettingsTab?, Bool) -> Void
    private let isSettingsVisible: () -> Bool

    init(
        accessController: AppAccessController,
        prepareSettings: @escaping (SettingsTab?, Bool) -> Void,
        openSettings: @escaping (SettingsTab?, Bool) -> Void,
        isSettingsVisible: @escaping () -> Bool
    ) {
        self.accessController = accessController
        self.prepare = prepareSettings
        self.open = openSettings
        self.isSettingsVisible = isSettingsVisible
    }

    func prepareSettings(initialTab: SettingsTab? = nil, presentsPaywall: Bool = false) {
        prepare(initialTab, presentsPaywall)
    }

    func openSettings(initialTab: SettingsTab? = nil, presentsPaywall: Bool = false) {
        open(initialTab, presentsPaywall)
    }

    /// Expiry asks the user to decide, so it opens the paywall rather than
    /// waiting to be found. Both triggers — a launch that resolves access, and
    /// the one-time nudge on Cmd+Tab — land here.
    ///
    /// The visibility guard is what keeps a second paywall from being asked
    /// for on top of the window already showing it.
    func handleExpiredAccess() {
        if !isSettingsVisible() {
            open(.about, true)
        }
        accessController.markPromptHandled()
    }

    static let lastTrialUsagePaywallDateKey = "lastTrialUsagePaywallDate"

    /// A running trial that has been used heavily gets the paywall once a day.
    /// The paywall sheet exists only on the App Store build.
    func handleTrialUsage(
        todayReopenCount: Int,
        now: Date = Date(),
        defaults: UserDefaults = .standard
    ) {
#if APPSTORE
        guard ReopenPolicy.shouldPresentTrialUsagePaywall(
            isTrialActive: accessController.entitlementState == .trial,
            trialStartedAt: defaults.object(forKey: AppDefaults.RawKey.trialStartDate) as? Date,
            todayReopenCount: todayReopenCount,
            lastPresentedDate: defaults.object(forKey: Self.lastTrialUsagePaywallDateKey) as? Date,
            now: now
        ), !isSettingsVisible() else {
            return
        }
        defaults.set(now, forKey: Self.lastTrialUsagePaywallDateKey)
        open(.about, true)
#endif
    }
}
