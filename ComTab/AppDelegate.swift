//
//  AppDelegate.swift
//  Command Reopen
//
//  Created by CHEN on 2025/10/31.
//

import AppKit
import Combine
import os

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusController: StatusBarController?
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
        AppLogger.lifecycle.notice("Application did finish launching. version=\(version) build=\(build)")
        NSApp.setActivationPolicy(.accessory)

        let proStatusManager = ProStatusManager.shared
        let shouldShowOnboarding = proStatusManager.isFirstLaunch
        proStatusManager.configureIfNeeded()
        bindUpgradePrompt(for: proStatusManager)
        statusController = StatusBarController(activationMonitor: .shared, proStatusManager: proStatusManager)

        // Ensure no windows are visible
        NSApp.windows.forEach { $0.orderOut(nil) }

        Task { @MainActor in
            await proStatusManager.refresh()
        }

        // Show onboarding on first launch
        if shouldShowOnboarding {
            DispatchQueue.main.async {
                OnboardingWindowController.shared.showIfNeeded(proStatusManager: proStatusManager)
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppLogger.lifecycle.notice("Application will terminate.")
    }

    private func bindUpgradePrompt(for proStatusManager: ProStatusManager) {
        proStatusManager.$shouldOpenProSettings
            .receive(on: RunLoop.main)
            .sink { shouldOpenProSettings in
                guard shouldOpenProSettings else {
                    return
                }

                if !SettingsWindowController.shared.isVisible {
                    SettingsWindowController.shared.show(
                        activationMonitor: .shared,
                        reopenStatsStore: .shared,
                        proStatusManager: proStatusManager,
                        initialTab: .pro
                    )
                }

                proStatusManager.markExpiredPromptHandled()
            }
            .store(in: &cancellables)
    }
}
