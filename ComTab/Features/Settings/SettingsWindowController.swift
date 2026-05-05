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
    static let shared = SettingsNavigationModel()

    @Published var selectedTab: SettingsTab
    @Published var isPaywallSheetPresented = false

    init(selectedTab: SettingsTab = .general) {
        self.selectedTab = selectedTab
    }
}

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()

    private static let frameAutosaveName = NSWindow.FrameAutosaveName("CommandReopen.SettingsWindow")
    private static let title = "Settings"

    private var window: NSWindow?

    var isVisible: Bool {
        window?.isVisible == true
    }

    func prepareForSettingsScene(
        accessController: AppAccessController? = nil,
        initialTab: SettingsTab? = nil,
        presentsPaywall: Bool = false
    ) {
        if let initialTab {
            AppLogger.lifecycle.notice("Preparing settings scene. initialTab=\(initialTab.rawValue)")
            SettingsNavigationModel.shared.selectedTab = initialTab
        } else {
            AppLogger.lifecycle.notice("Preparing settings scene. Restoring existing selected tab.")
        }

        if presentsPaywall {
            SettingsNavigationModel.shared.isPaywallSheetPresented = true
        }
    }

    func show(
        activationMonitor: ActivationMonitor? = nil,
        reopenStatsStore: ReopenStatsStore? = nil,
        accessController: AppAccessController? = nil,
        initialTab: SettingsTab? = nil,
        presentsPaywall: Bool = false
    ) {
        prepareForSettingsScene(accessController: accessController, initialTab: initialTab, presentsPaywall: presentsPaywall)
        if let window {
            present(window)
            return
        }

        let window = makeWindow(
            activationMonitor: activationMonitor ?? .shared,
            reopenStatsStore: reopenStatsStore ?? .shared,
            accessController: accessController ?? .shared
        )
        self.window = window
        present(window)
    }

    private func activateApp() {
        NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps])

        if #available(macOS 14.0, *) {
            NSApplication.shared.activate()
        } else {
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }

    private func makeWindow(
        activationMonitor: ActivationMonitor,
        reopenStatsStore: ReopenStatsStore,
        accessController: AppAccessController
    ) -> NSWindow {
        let rootView = SettingsWindowRootView(
            activationMonitor: activationMonitor,
            reopenStatsStore: reopenStatsStore,
            accessController: accessController,
            settingsNavigationModel: .shared
        )
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = Self.title
        window.delegate = self
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName(Self.frameAutosaveName)
        if !window.setFrameUsingName(Self.frameAutosaveName) {
            window.center()
        }
        return window
    }

    private func present(_ window: NSWindow) {
        activateApp()
        window.makeKeyAndOrderFront(nil)
        window.setFrameUsingName(Self.frameAutosaveName)
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}

private struct SettingsWindowRootView: View {
    @ObservedObject var activationMonitor: ActivationMonitor
    @ObservedObject var reopenStatsStore: ReopenStatsStore
    @ObservedObject var accessController: AppAccessController
    @ObservedObject var settingsNavigationModel: SettingsNavigationModel
#if APPSTORE
    @StateObject private var proStatusManager = ProStatusManager.shared
#endif

    var body: some View {
        SettingsView()
            .environmentObject(activationMonitor)
            .environmentObject(reopenStatsStore)
            .environmentObject(accessController)
            .environmentObject(settingsNavigationModel)
#if APPSTORE
            .environmentObject(proStatusManager)
#endif
    }
}
