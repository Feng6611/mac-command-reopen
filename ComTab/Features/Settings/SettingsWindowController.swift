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

    private static let frameAutosaveName = NSWindow.FrameAutosaveName("CommandReopen.SettingsWindow")

    private var openSettingsAction: (() -> Void)?

    var isVisible: Bool {
        visibleSettingsWindows.isEmpty == false
    }

    func installOpenSettingsAction(_ action: @escaping () -> Void) {
        openSettingsAction = action
    }

    func prepareForSettingsScene(
        accessController: AppAccessController? = nil,
        initialTab: SettingsTab? = nil
    ) {
        let accessController = accessController ?? .shared
        let resolvedInitialTab = initialTab.flatMap { requestedTab in
            accessController.showsProTab || requestedTab != .pro ? requestedTab : .general
        }

        if let resolvedInitialTab {
            AppLogger.lifecycle.notice("Preparing settings scene. initialTab=\(resolvedInitialTab.rawValue)")
            SettingsNavigationModel.shared.selectedTab = resolvedInitialTab
        } else if !accessController.showsProTab && SettingsNavigationModel.shared.selectedTab == .pro {
            AppLogger.lifecycle.notice("Preparing settings scene. selected pro tab is unavailable; falling back to general.")
            SettingsNavigationModel.shared.selectedTab = .general
        } else {
            AppLogger.lifecycle.notice("Preparing settings scene. Restoring existing selected tab.")
        }

        activateApp()
        DispatchQueue.main.async { [weak self] in
            self?.restoreSettingsWindowFrame()
        }
    }

    func show(
        activationMonitor: ActivationMonitor? = nil,
        reopenStatsStore: ReopenStatsStore? = nil,
        accessController: AppAccessController? = nil,
        initialTab: SettingsTab? = nil
    ) {
        prepareForSettingsScene(accessController: accessController, initialTab: initialTab)
        if let openSettingsAction {
            openSettingsAction()
        } else {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
    }

    private func activateApp() {
        NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps])

        if #available(macOS 14.0, *) {
            NSApplication.shared.activate()
        } else {
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }

    private var visibleSettingsWindows: [NSWindow] {
        NSApp.windows.filter { window in
            window.isVisible && isSettingsWindow(window)
        }
    }

    private func restoreSettingsWindowFrame() {
        for window in visibleSettingsWindows {
            window.center()
            window.setFrameUsingName(Self.frameAutosaveName)
            window.setFrameAutosaveName(Self.frameAutosaveName)
        }
    }

    private func isSettingsWindow(_ window: NSWindow) -> Bool {
        window.title == "Settings"
    }
}

@available(macOS 14.0, *)
struct SettingsOpenActionInstaller: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                SettingsWindowController.shared.installOpenSettingsAction {
                    openSettings()
                }
            }
    }
}
