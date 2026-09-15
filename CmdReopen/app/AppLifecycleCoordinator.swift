//
//  AppLifecycleCoordinator.swift
//  CmdReopen
//
//  Created by Codex on 2026/4/26.
//

import AppKit
import Combine
import Defaults
import os
#if APPSTORE
import KikiCommerceCore
#endif

@MainActor
final class AppLifecycleCoordinator {
    private enum Constants {
        static let commerceRefreshThrottle: TimeInterval = 5 * 60
        static let reviewPromptDelayNanoseconds: UInt64 = 1_500_000_000
    }

    static var shared: AppLifecycleCoordinator { AppComposition.shared.lifecycle }

    private let accessController: AppAccessController
    private let statusBarController: StatusBarMenuController
    private let activationMonitor: ActivationMonitor
    private let reopenStatsStore: ReopenStatsStore
    private let router: AppRouter
    private let launchSource: LaunchSourceProviding
    private let iconSettings: MenuBarIconSettings
    private var cancellables: Set<AnyCancellable> = []
    private var hasCompletedInitialCommerceRefresh = false
    private var lastCommerceRefreshAt: Date?
    private var isRefreshingCommerce = false
    /// Captured at launch: the login-item attribute is only readable while the
    /// launch Apple Event is being processed, so it cannot be looked up later.
    private var isLoginItemLaunch = false
    private var didOpenSettingsForLaunch = false
#if DEBUG
    private var isRelaunchedForOnboarding = false
#endif

    init(accessController: AppAccessController,
         statusBarController: StatusBarMenuController,
         activationMonitor: ActivationMonitor,
         reopenStatsStore: ReopenStatsStore,
         router: AppRouter,
         launchSource: LaunchSourceProviding,
         iconSettings: MenuBarIconSettings) {
        self.accessController = accessController
        self.statusBarController = statusBarController
        self.activationMonitor = activationMonitor
        self.reopenStatsStore = reopenStatsStore
        self.router = router
        self.launchSource = launchSource
        self.iconSettings = iconSettings
    }

    func applicationWillFinishLaunching() {
        // Onboarding runs the Cmd+Tab tutorial, which needs a real app to tab
        // to and from, so a launch that will present it starts as .regular.
        // Every other launch is the steady state: menu bar only.
#if DEBUG
        isRelaunchedForOnboarding = OnboardingLaunchRequest.consume()
        let shouldStartRegular = isRelaunchedForOnboarding || accessController.shouldShowOnboarding
#else
        let shouldStartRegular = accessController.shouldShowOnboarding
#endif
        NSApp.setActivationPolicy(shouldStartRegular ? .regular : .accessory)
    }

    func applicationDidFinishLaunching() {
        isLoginItemLaunch = launchSource.isLoginItemLaunch

        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
        AppLogger.lifecycle.notice("Application did finish launching. version=\(version) build=\(build) loginItem=\(self.isLoginItemLaunch, privacy: .public)")
        statusBarController.install(
            activationMonitor: activationMonitor,
            accessController: accessController
        )
#if DIRECT
        DockClickMonitor.shared.start(
            isEnabled: {
                AdvancedWindowRestoreSettings.shared.isAdvancedModeEnabled
                    && AdvancedWindowRestoreSettings.shared.cyclesWindowsFromDockClick
                    && self.activationMonitor.isFeatureEnabled
                    && self.accessController.isCoreFeatureAvailable
            },
            onDockAppIntent: { bundleIdentifier, processIdentifier, date, targetWasFrontmost in
                self.activationMonitor.registerPendingDockClick(
                    bundleIdentifier: bundleIdentifier,
                    processIdentifier: processIdentifier,
                    at: date,
                    targetWasFrontmost: targetWasFrontmost
                )
            },
            onDockAppClick: { intent in
                self.activationMonitor.cycleWindowsForConfirmedDockClick(intent)
            }
        )
#endif
        bindUpgradePrompt()
        scheduleLaunchReviewRequest()

        // Ensure no windows are visible for the menu-bar-only idle state.
        NSApp.windows.forEach { $0.orderOut(nil) }

#if DEBUG
        if shouldAutoShowSettingsForDebugLaunch && !isRelaunchedForOnboarding {
            AppLogger.lifecycle.notice("Debug launch detected. Opening settings window for visibility.")
            didOpenSettingsForLaunch = true
            router.openSettings()
        }
#endif

#if APPSTORE
        // The App Store build waits for the first commerce result before
        // presenting: onboarding's copy and its trial depend on it.
        scheduleInitialCommerceRefresh()
#else
        hasCompletedInitialCommerceRefresh = true
        if accessController.shouldShowOnboarding {
            OnboardingWindowController.shared.showIfNeeded(accessController: accessController)
        } else {
            presentSettingsForLaunchIfNeeded()
        }
#endif
    }

    /// Opening a running copy is the way back into Settings once the menu bar
    /// icon is hidden, so it is handled here rather than left to AppKit.
    func applicationShouldHandleReopen() {
        guard LaunchPresentationPolicy.shouldOpenSettingsOnReopen(
            showsMenuBarIcon: iconSettings.showsMenuBarIcon,
            isOnboardingVisible: isOnboardingVisible
        ) else {
            return
        }

        AppLogger.lifecycle.notice("Re-launch with the menu bar icon hidden. Opening Settings.")
        router.openSettings()
    }

    func applicationDidBecomeActive() {
        AppLogger.lifecycle.debug("Application became active. Evaluating commerce refresh throttle.")
        guard accessController.hasLoadedCommerceStateSource else {
            return
        }
        Task { @MainActor in
            await refreshCommerceStateIfNeeded(force: false, reason: "applicationDidBecomeActive")
        }
    }

    func applicationWillTerminate() {
        AppLogger.lifecycle.notice("Application will terminate.")
#if DIRECT
        DockClickMonitor.shared.stop()
#endif
        reopenStatsStore.flush()
    }

#if DEBUG
    private var shouldAutoShowSettingsForDebugLaunch: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["OS_ACTIVITY_DT_MODE"] == "1" || environment["OS_ACTIVITY_DT_MODE"] == "YES"
    }
#endif

    private func bindUpgradePrompt() {
        guard cancellables.isEmpty else {
            return
        }

        accessController.$shouldOpenProSettings
            .receive(on: RunLoop.main)
            .sink { [weak self] shouldOpenProSettings in
                guard let self else {
                    return
                }
                guard shouldOpenProSettings else {
                    return
                }
                guard self.hasCompletedInitialCommerceRefresh else {
                    return
                }
                guard !self.isOnboardingVisible else {
                    return
                }

                self.router.handleExpiredAccess()
            }
            .store(in: &cancellables)
    }

    private func completeInitialCommerceRefresh() async {
        await refreshCommerceStateIfNeeded(force: true, reason: "initialLaunch")
        hasCompletedInitialCommerceRefresh = true

#if APPSTORE
#if DEBUG
        if isRelaunchedForOnboarding {
            isRelaunchedForOnboarding = false
            OnboardingWindowController.shared.showAfterDebugRelaunch()
            return
        }
#endif

        if accessController.allowsAutomaticAccessPresentation,
           accessController.shouldShowOnboarding {
            OnboardingWindowController.shared.showIfNeeded(accessController: accessController)
            return
        }
#endif

        // An onboarding window opened from Settings is visible without this
        // launch having presented it, so the paywall waits rather than landing
        // on top of the tutorial.
        if accessController.shouldOpenProSettings, !isOnboardingVisible {
            router.handleExpiredAccess()
            // The paywall is this launch's foreground presentation, so the
            // hidden-icon rule below must not ask for Settings a second time.
            didOpenSettingsForLaunch = true
        }

        presentSettingsForLaunchIfNeeded()
    }

    /// Brings up Settings when this launch is the user's only way in.
    ///
    /// With the menu bar icon hidden, launching the app is the entrance the
    /// product promises, so a deliberate launch opens Settings while a
    /// login-item launch and a launch that is presenting onboarding do not.
    private func presentSettingsForLaunchIfNeeded() {
        guard !didOpenSettingsForLaunch else {
            return
        }

        guard LaunchPresentationPolicy.shouldOpenSettingsAtLaunch(
            isLoginItemLaunch: isLoginItemLaunch,
            showsMenuBarIcon: iconSettings.showsMenuBarIcon,
            shouldShowOnboarding: isOnboardingTakingOver
        ) else {
            return
        }

        didOpenSettingsForLaunch = true
        AppLogger.lifecycle.notice("Menu bar icon hidden. Opening Settings for this launch.")
        router.openSettings()
    }

    /// Whether onboarding owns this launch's foreground presentation.
    private var isOnboardingTakingOver: Bool {
#if DEBUG
        isRelaunchedForOnboarding || accessController.shouldShowOnboarding
#else
        accessController.shouldShowOnboarding
#endif
    }

    private func scheduleInitialCommerceRefresh() {
        Task { @MainActor [weak self] in
            await Task.yield()
            await self?.completeInitialCommerceRefresh()
        }
    }

    private func scheduleLaunchReviewRequest() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: Constants.reviewPromptDelayNanoseconds)
            _ = reopenStatsStore.requestReviewIfEligible(for: .applicationLaunched)
        }
    }

    private var isOnboardingVisible: Bool {
#if APPSTORE
        OnboardingWindowController.shared.isVisible
#else
        false
#endif
    }

    /// Checks purchases at the moment the user can see the answer.
    ///
    /// The two scheduled checks — one at launch, one throttled to five minutes
    /// on activation — both happen away from the pane that displays the
    /// result. A launch check that failed, or that is still waiting on
    /// StoreKit, therefore left the About row reading "checking purchases"
    /// with nothing on its way to replace it. Opening Settings is the one
    /// moment the answer is being read, so it is worth asking again; the
    /// throttle is waived only while no check has ever resolved.
    func refreshCommerceStateForSettings() async {
        await refreshCommerceStateIfNeeded(
            force: !hasResolvedCommerceReadiness,
            reason: "settingsOpened"
        )
    }

    private var hasResolvedCommerceReadiness: Bool {
        accessController.hasResolvedInitialCommerceRefresh
    }

    private func refreshCommerceStateIfNeeded(force: Bool, reason: String) async {
        if isRefreshingCommerce {
            AppLogger.lifecycle.debug("Skipping commerce refresh for \(reason) because another refresh is already running.")
            return
        }

        let now = Date()
        if !force,
           let lastCommerceRefreshAt,
           now.timeIntervalSince(lastCommerceRefreshAt) < Constants.commerceRefreshThrottle {
            AppLogger.lifecycle.debug("Skipping commerce refresh for \(reason) because the last refresh was too recent.")
            return
        }

        isRefreshingCommerce = true
        defer {
            isRefreshingCommerce = false
            lastCommerceRefreshAt = Date()
        }

        await accessController.refresh()
    }
}
