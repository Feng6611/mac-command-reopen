//
//  SettingsWindowController.swift
//  ComTab
//
//  Created by Codex on 2026/3/28.
//

import AppKit
import Combine
import SwiftUI
import os

@MainActor
final class SettingsNavigationModel: ObservableObject {
    @Published var selectedTab: SettingsTab

    init(selectedTab: SettingsTab = .general) {
        self.selectedTab = selectedTab
    }
}

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()

    private var window: NSWindow?
    private var hostingController: NSHostingController<AnyView>?
    private let navigationModel = SettingsNavigationModel()

    var isVisible: Bool {
        window?.isVisible == true
    }

    func show(
        activationMonitor: ActivationMonitor? = nil,
        reopenStatsStore: ReopenStatsStore? = nil,
        accessController: AppAccessController? = nil,
        initialTab: SettingsTab = .general
    ) {
        let activationMonitor = activationMonitor ?? .shared
        let reopenStatsStore = reopenStatsStore ?? .shared
        let accessController = accessController ?? .shared
        let resolvedInitialTab: SettingsTab = accessController.showsProTab ? initialTab : .general

        if let window {
            AppLogger.lifecycle.debug("Reusing existing settings window. initialTab=\(resolvedInitialTab.rawValue)")
            navigationModel.selectedTab = resolvedInitialTab
            present(window)
            return
        }

        navigationModel.selectedTab = resolvedInitialTab

        let hostingController = NSHostingController(
            rootView: makeRootView(
                activationMonitor: activationMonitor,
                reopenStatsStore: reopenStatsStore,
                accessController: accessController,
                navigationModel: navigationModel
            )
        )
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Settings"
        window.delegate = self
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.collectionBehavior = [.moveToActiveSpace]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 600, height: 520))
        window.center()
        window.setFrameAutosaveName("CommandReopenSettingsWindow")

        self.window = window
        self.hostingController = hostingController

        AppLogger.lifecycle.notice("Showing settings window. initialTab=\(resolvedInitialTab.rawValue)")
        present(window)
    }

    private func makeRootView(
        activationMonitor: ActivationMonitor,
        reopenStatsStore: ReopenStatsStore,
        accessController: AppAccessController,
        navigationModel: SettingsNavigationModel
    ) -> AnyView {
        let rootView =
            SettingsView()
                .environmentObject(activationMonitor)
                .environmentObject(reopenStatsStore)
                .environmentObject(accessController)
                .environmentObject(navigationModel)
#if APPSTORE
                .environmentObject(ProStatusManager.shared)
#endif

        return AnyView(rootView)
    }

    private func present(_ window: NSWindow) {
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }

        NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps])
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
        hostingController = nil
    }
}
