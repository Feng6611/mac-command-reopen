import Foundation

/// Owns the long-lived application graph. Compatibility `shared` properties
/// forward here; they never construct a second mutable service.
@MainActor
final class AppComposition {
    static let shared = AppComposition()

    lazy var accessController = AppAccessController.makeDefault()
    lazy var reopenStats = ReopenStatsStore()
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
    lazy var commandAccess = CommandAccessModel()
    lazy var commerceSource = ProCommerceStateSource(proStatusManager: commandAccess)
#endif
}
