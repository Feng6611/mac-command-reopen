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
final class SettingsWindowController {
    static let shared = SettingsWindowController()

    private static let frameAutosaveName = NSWindow.FrameAutosaveName("CommandReopen.SettingsWindow")

    var isVisible: Bool {
        visibleSettingsWindows.isEmpty == false
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

        activateApp()
        DispatchQueue.main.async { [weak self] in
            self?.restoreSettingsWindowFrame()
        }
    }

    func show(
        activationMonitor: ActivationMonitor? = nil,
        reopenStatsStore: ReopenStatsStore? = nil,
        accessController: AppAccessController? = nil,
        initialTab: SettingsTab? = nil,
        presentsPaywall: Bool = false
    ) {
        SettingsOpener.shared.open(initialTab: initialTab, presentsPaywall: presentsPaywall)
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
            window.contentMinSize = CGSize(width: DS.Window.settingsWidth, height: DS.Window.settingsHeight)
            window.center()
            window.setFrameUsingName(Self.frameAutosaveName)
            window.setFrameAutosaveName(Self.frameAutosaveName)
            enforceMinimumContentSize(for: window)
        }
    }

    private func enforceMinimumContentSize(for window: NSWindow) {
        let currentContentSize = window.contentLayoutRect.size
        let minimumContentSize = CGSize(width: DS.Window.settingsWidth, height: DS.Window.settingsHeight)
        guard currentContentSize.width < minimumContentSize.width
                || currentContentSize.height < minimumContentSize.height else {
            return
        }

        var frame = window.frame
        let targetContentSize = CGSize(
            width: max(currentContentSize.width, minimumContentSize.width),
            height: max(currentContentSize.height, minimumContentSize.height)
        )
        let targetFrame = window.frameRect(forContentRect: CGRect(origin: .zero, size: targetContentSize))
        frame.size.width = targetFrame.size.width
        frame.size.height = targetFrame.size.height
        window.setFrame(frame, display: true)
    }

    private func isSettingsWindow(_ window: NSWindow) -> Bool {
        window.title == "Settings"
    }
}

@MainActor
final class SettingsOpener {
    static let shared = SettingsOpener()

    func prepare(initialTab: SettingsTab? = nil, presentsPaywall: Bool = false) {
        SettingsWindowController.shared.prepareForSettingsScene(
            initialTab: initialTab,
            presentsPaywall: presentsPaywall
        )
    }

    func open(initialTab: SettingsTab? = nil, presentsPaywall: Bool = false) {
        prepare(initialTab: initialTab, presentsPaywall: presentsPaywall)

        if performMainMenuSettingsItem() {
            return
        }

        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    private func performMainMenuSettingsItem() -> Bool {
        guard let mainMenu = NSApp.mainMenu else {
            AppLogger.lifecycle.debug("Unable to open settings through main menu because NSApp.mainMenu is nil.")
            return false
        }

        return performSettingsItem(in: mainMenu)
    }

    private func performSettingsItem(in menu: NSMenu) -> Bool {
        for (index, item) in menu.items.enumerated() {
            if isSettingsItem(item), item.isEnabled {
                menu.performActionForItem(at: index)
                return true
            }

            if let submenu = item.submenu,
               performSettingsItem(in: submenu) {
                return true
            }
        }

        return false
    }

    private func isSettingsItem(_ item: NSMenuItem) -> Bool {
        if item.keyEquivalent == "," {
            return true
        }

        let normalizedTitle = item.title
            .replacingOccurrences(of: "…", with: "...")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        return normalizedTitle == "settings..."
            || normalizedTitle == "preferences..."
    }
}
