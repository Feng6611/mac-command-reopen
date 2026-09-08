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
    private var cancellables: Set<AnyCancellable> = []
    private var hasCompletedInitialCommerceRefresh = false
    private var lastCommerceRefreshAt: Date?
    private var isRefreshingCommerce = false
#if DEBUG
    private var isRelaunchedForOnboarding = false
#endif

    init(accessController: AppAccessController,
         statusBarController: StatusBarMenuController,
         activationMonitor: ActivationMonitor,
         reopenStatsStore: ReopenStatsStore,
         router: AppRouter) {
        self.accessController = accessController
        self.statusBarController = statusBarController
        self.activationMonitor = activationMonitor
        self.reopenStatsStore = reopenStatsStore
        self.router = router
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
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
        AppLogger.lifecycle.notice("Application did finish launching. version=\(version) build=\(build)")
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
        }
#endif
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

        if accessController.shouldOpenProSettings {
            router.handleExpiredAccess()
        }
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
