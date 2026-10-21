import Foundation
import KikiAnalytics

/// Owns the long-lived application graph. Compatibility `shared` properties
/// forward here; they never construct a second mutable service.
@MainActor
final class AppComposition {
    static let shared = AppComposition()

    lazy var accessController = AppAccessController.makeDefault()
    lazy var analytics: KikiAnalytics = CommandReopenAnalytics.make(
        entitlementState: { [weak self] in self?.accessController.entitlementState ?? .expired }
    )
    lazy var reopenStats: ReopenStatsStore = {
        let store = ReopenStatsStore(isReviewAudienceEligible: { [weak self] in
            // Only ask someone the app is currently working for.
            self?.accessController.isCoreFeatureAvailable ?? false
        })
        store.onReopenRecorded = { [weak self] todayCount in
            guard let self else { return }
            // A successful, non-helper reopen is the day's value.
            self.analytics.track(KikiStandardEvent.valueDay(changes: store.totalSuccessfulReopens))
            self.router.handleTrialUsage(todayReopenCount: todayCount)
        }
        return store
    }()
    lazy var settingsNavigation = SettingsNavigationModel()
    lazy var settingsWindow: SettingsWindowController = SettingsWindowController(navigation: settingsNavigation) { [weak self] in
        Task { await self?.lifecycle.refreshCommerceStateForSettings() }
    }
    lazy var router: AppRouter = AppRouter(
        accessController: accessController,
        prepareSettings: { [weak self] tab, paywall in
            self?.settingsWindow.prepareForSettingsScene(initialTab: tab, presentsPaywall: paywall)
        },
        openSettings: { [weak self] tab, paywall in
            self?.settingsWindow.show(initialTab: tab, presentsPaywall: paywall)
        },
        isSettingsVisible: { [weak self] in
            self?.settingsWindow.isVisible ?? false
        }
    )
    lazy var activationMonitor: ActivationMonitor = ActivationMonitor(
        reopenStatsStore: reopenStats,
        accessController: accessController,
        onExpiredReopenNeeded: { [weak self] in self?.router.handleExpiredAccess() }
    )
    lazy var menuBarIconSettings = MenuBarIconSettings.shared
    lazy var statusBar = StatusBarMenuController(iconSettings: menuBarIconSettings)
    lazy var lifecycle: AppLifecycleCoordinator = AppLifecycleCoordinator(
        accessController: accessController,
        statusBarController: statusBar,
        activationMonitor: activationMonitor,
        reopenStatsStore: reopenStats,
        router: router,
        launchSource: SystemLaunchSource(),
        iconSettings: menuBarIconSettings
    )
#if APPSTORE
    lazy var commandAccess = CommandAccessModel(
        postHogUserID: analytics.installationID.uuidString
    )
    lazy var commerceSource = ProCommerceStateSource(proStatusManager: commandAccess)
#endif
}
