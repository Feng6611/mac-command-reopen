//
//  AppLifecycleCoordinator.swift
//  ComTab
//
//  Created by Codex on 2026/4/26.
//

import AppKit
import Combine
import os

@MainActor
final class AppLifecycleCoordinator {
    private enum Constants {
        static let commerceRefreshThrottle: TimeInterval = 5 * 60
    }

    static let shared = AppLifecycleCoordinator()

    private let accessController: AppAccessController
    private var cancellables: Set<AnyCancellable> = []
    private var hasCompletedInitialCommerceRefresh = false
    private var lastCommerceRefreshAt: Date?
    private var isRefreshingCommerce = false

    init(accessController: AppAccessController? = nil) {
        self.accessController = accessController ?? .shared
    }

    func applicationDidFinishLaunching() {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
        AppLogger.lifecycle.notice("Application did finish launching. version=\(version) build=\(build)")
        NSApp.setActivationPolicy(.accessory)
        accessController.configureIfNeeded()
        bindUpgradePrompt()

#if APPSTORE
        let shouldShowOnboardingImmediately = accessController.shouldShowOnboarding
        if shouldShowOnboardingImmediately {
            OnboardingWindowController.shared.showIfNeeded(proStatusManager: .shared)
            hasCompletedInitialCommerceRefresh = true
        }
#else
        let shouldShowOnboardingImmediately = false
#endif

        if !shouldShowOnboardingImmediately {
            // Ensure no windows are visible for the menu-bar-only idle state.
            NSApp.windows.forEach { $0.orderOut(nil) }
        }

#if DEBUG
        if shouldAutoShowSettingsForDebugLaunch, !shouldShowOnboardingImmediately {
            AppLogger.lifecycle.notice("Debug launch detected. Opening settings window for visibility.")
            SettingsWindowController.shared.show(
                activationMonitor: .shared,
                reopenStatsStore: .shared,
                accessController: accessController
            )
        }
#endif

        guard !shouldShowOnboardingImmediately else {
            return
        }

        Task { @MainActor in
            await completeInitialCommerceRefresh()
        }
    }

    func applicationDidBecomeActive() {
        AppLogger.lifecycle.debug("Application became active. Evaluating commerce refresh throttle.")
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
                        initialTab: .pro
                    )
                }

                self.accessController.markPromptHandled()
            }
            .store(in: &cancellables)
    }

    private func completeInitialCommerceRefresh() async {
        await refreshCommerceStateIfNeeded(force: true, reason: "initialLaunch")
        hasCompletedInitialCommerceRefresh = true

        if accessController.shouldOpenProSettings, !isOnboardingVisible {
            if !SettingsWindowController.shared.isVisible {
                SettingsWindowController.shared.show(
                    activationMonitor: .shared,
                    reopenStatsStore: .shared,
                    accessController: accessController,
                    initialTab: .pro
                )
            }

            accessController.markPromptHandled()
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
        if accessController.shouldShowOnboarding && !hasCompletedInitialCommerceRefresh {
            AppLogger.lifecycle.debug("Skipping commerce refresh for \(reason) because onboarding is pending.")
            return
        }

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
