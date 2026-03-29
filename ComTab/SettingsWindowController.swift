//
//  SettingsWindowController.swift
//  ComTab
//
//  Created by Codex on 2026/3/28.
//

import AppKit
import SwiftUI
import os

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()

    private var window: NSWindow?
    private var hostingController: NSHostingController<AnyView>?

    var isVisible: Bool {
        window?.isVisible == true
    }

    func show(
        activationMonitor: ActivationMonitor? = nil,
        reopenStatsStore: ReopenStatsStore? = nil,
        proStatusManager: ProStatusManager? = nil,
        initialTab: SettingsTab = .general
    ) {
        let activationMonitor = activationMonitor ?? .shared
        let reopenStatsStore = reopenStatsStore ?? .shared
        let proStatusManager = proStatusManager ?? .shared

        if let window {
            AppLogger.lifecycle.debug("Reusing existing settings window. initialTab=\(initialTab.rawValue)")
            // Replace the hosting controller to guarantee @State is reset with the new initialTab
            let newHostingController = NSHostingController(
                rootView: makeRootView(
                    activationMonitor: activationMonitor,
                    reopenStatsStore: reopenStatsStore,
                    proStatusManager: proStatusManager,
                    initialTab: initialTab
                )
            )
            window.contentViewController = newHostingController
            self.hostingController = newHostingController
            NSApplication.shared.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let hostingController = NSHostingController(
            rootView: makeRootView(
                activationMonitor: activationMonitor,
                reopenStatsStore: reopenStatsStore,
                proStatusManager: proStatusManager,
                initialTab: initialTab
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

        AppLogger.lifecycle.notice("Showing settings window. initialTab=\(initialTab.rawValue)")
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    private func makeRootView(
        activationMonitor: ActivationMonitor,
        reopenStatsStore: ReopenStatsStore,
        proStatusManager: ProStatusManager,
        initialTab: SettingsTab
    ) -> AnyView {
        AnyView(
            SettingsView(initialTab: initialTab)
                .environmentObject(activationMonitor)
                .environmentObject(reopenStatsStore)
                .environmentObject(proStatusManager)
        )
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
        hostingController = nil
    }
}
