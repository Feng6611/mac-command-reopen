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
    private let accessController = AppAccessController.shared
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
        AppLogger.lifecycle.notice("Application did finish launching. version=\(version) build=\(build)")
        NSApp.setActivationPolicy(.accessory)
        accessController.configureIfNeeded()
        let shouldShowOnboarding = accessController.shouldShowOnboarding
        bindUpgradePrompt()
        statusController = StatusBarController(activationMonitor: .shared, accessController: accessController)

        // Ensure no windows are visible
        NSApp.windows.forEach { $0.orderOut(nil) }

        Task { @MainActor in
            await accessController.refresh()
        }

        // Show onboarding on first launch
        if shouldShowOnboarding {
#if APPSTORE
            DispatchQueue.main.async {
                OnboardingWindowController.shared.showIfNeeded(proStatusManager: .shared)
            }
#endif
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        AppLogger.lifecycle.debug("Application became active. Refreshing commerce state.")
        Task { @MainActor in
            await accessController.refresh()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppLogger.lifecycle.notice("Application will terminate.")
    }

    private func bindUpgradePrompt() {
        accessController.$shouldOpenProSettings
            .receive(on: RunLoop.main)
            .sink { shouldOpenProSettings in
                guard shouldOpenProSettings else {
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
}
