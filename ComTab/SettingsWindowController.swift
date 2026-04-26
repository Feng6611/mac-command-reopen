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

    init(selectedTab: SettingsTab = .general) {
        self.selectedTab = selectedTab
    }
}

@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()

    var isVisible: Bool {
        NSApp.windows.contains { window in
            window.isVisible && window.title == "Settings"
        }
    }

    func prepareForSettingsScene(
        accessController: AppAccessController? = nil,
        initialTab: SettingsTab = .general
    ) {
        let accessController = accessController ?? .shared
        let resolvedInitialTab: SettingsTab = accessController.showsProTab ? initialTab : .general

        AppLogger.lifecycle.notice("Preparing settings scene. initialTab=\(resolvedInitialTab.rawValue)")
        SettingsNavigationModel.shared.selectedTab = resolvedInitialTab

        NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps])
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func show(
        activationMonitor: ActivationMonitor? = nil,
        reopenStatsStore: ReopenStatsStore? = nil,
        accessController: AppAccessController? = nil,
        initialTab: SettingsTab = .general
    ) {
        prepareForSettingsScene(accessController: accessController, initialTab: initialTab)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
}
