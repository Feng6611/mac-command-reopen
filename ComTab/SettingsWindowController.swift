//
//  SettingsWindowController.swift
//  ComTab
//
//  Created by Codex on 2026/3/28.
//

import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    func show(
        activationMonitor: ActivationMonitor? = nil,
        reopenStatsStore: ReopenStatsStore? = nil
    ) {
        if let window {
            NSApplication.shared.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let activationMonitor = activationMonitor ?? .shared
        let reopenStatsStore = reopenStatsStore ?? .shared
        let contentView = SettingsView()
            .environmentObject(activationMonitor)
            .environmentObject(reopenStatsStore)

        let hostingController = NSHostingController(rootView: contentView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Settings"
        window.delegate = self
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 420, height: 560))
        window.center()
        window.setFrameAutosaveName("CommandReopenSettingsWindow")

        self.window = window

        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}
