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

    static let shared = AppLifecycleCoordinator()

    private let accessController: AppAccessController
    private let statusBarController: StatusBarMenuController
    private var cancellables: Set<AnyCancellable> = []
    private var hasCompletedInitialCommerceRefresh = false
    private var lastCommerceRefreshAt: Date?
    private var isRefreshingCommerce = false
#if DEBUG
    private var isRelaunchedForOnboarding = false
#endif

    init(accessController: AppAccessController? = nil,
         statusBarController: StatusBarMenuController? = nil) {
        self.accessController = accessController ?? .shared
        self.statusBarController = statusBarController ?? .shared
    }

    func applicationWillFinishLaunching() {
#if APPSTORE
#if DEBUG
        isRelaunchedForOnboarding = OnboardingLaunchRequest.consume()
        let shouldStartRegular = isRelaunchedForOnboarding || CommandAccessModel.shared.isFirstLaunch
#else
        let shouldStartRegular = CommandAccessModel.shared.isFirstLaunch
#endif
        NSApp.setActivationPolicy(shouldStartRegular ? .regular : .accessory)
#else
        NSApp.setActivationPolicy(.accessory)
#endif
    }

    func applicationDidFinishLaunching() {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
        AppLogger.lifecycle.notice("Application did finish launching. version=\(version) build=\(build)")
        statusBarController.install(
            activationMonitor: .shared,
            accessController: accessController
        )
        CommandReopenAnalytics.shared.configureIfPossible()
        CommandReopenAnalytics.shared.captureFirstOpen(
            entitlementState: accessController.entitlementState.analyticsValue
        )
        bindUpgradePrompt()
        scheduleLaunchReviewRequest()

        // Ensure no windows are visible for the menu-bar-only idle state.
        NSApp.windows.forEach { $0.orderOut(nil) }

#if DEBUG
        if shouldAutoShowSettingsForDebugLaunch && !isRelaunchedForOnboarding {
            AppLogger.lifecycle.notice("Debug launch detected. Opening settings window for visibility.")
            SettingsWindowController.shared.show(
                activationMonitor: .shared,
                reopenStatsStore: .shared,
                accessController: accessController
            )
        }
#endif

#if APPSTORE
        scheduleInitialCommerceRefresh()
#else
        hasCompletedInitialCommerceRefresh = true
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

                if !SettingsWindowController.shared.isVisible {
                    SettingsWindowController.shared.show(
                        activationMonitor: .shared,
                        reopenStatsStore: .shared,
                        accessController: self.accessController,
                        initialTab: .about,
                        presentsPaywall: true,
                        paywallSource: .trialExpiredLaunch
                    )
                }

                self.accessController.markPromptHandled()
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
            OnboardingWindowController.shared.showAfterDebugRelaunch(proStatusManager: .shared)
            return
        }
#endif

        if CommandAccessModel.shared.readiness.allowsAutomaticPresentation,
           accessController.shouldShowOnboarding {
            OnboardingWindowController.shared.showIfNeeded(proStatusManager: .shared)
            return
        }
#endif

        if accessController.shouldOpenProSettings, !isOnboardingVisible {
            if !SettingsWindowController.shared.isVisible {
                SettingsWindowController.shared.show(
                    activationMonitor: .shared,
                    reopenStatsStore: .shared,
                    accessController: accessController,
                    initialTab: .about,
                    presentsPaywall: true,
                    paywallSource: .trialExpiredLaunch
                )
            }

            accessController.markPromptHandled()
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
            _ = ReopenStatsStore.shared.requestReviewIfEligible(for: .applicationLaunched)
        }
    }

    private var isOnboardingVisible: Bool {
#if APPSTORE
        OnboardingWindowController.shared.isVisible
#else
        false
#endif
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
