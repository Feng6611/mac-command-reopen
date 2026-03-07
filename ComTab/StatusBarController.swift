//
//  StatusBarController.swift
//  Command Reopen
//
//  Created by CHEN on 2025/10/31.
//

import AppKit
import Combine

final class StatusBarController: NSObject {
    private let statusItem: NSStatusItem
    private let activationMonitor: ActivationMonitor
    private let launchManager = LaunchAtLoginManager()
    private var cancellables: Set<AnyCancellable> = []
    private var enableReopenItem: NSMenuItem?

    init(activationMonitor: ActivationMonitor = .shared) {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.activationMonitor = activationMonitor
        super.init()
        configureButton()
        constructMenu()
        bindMenuState()
    }

    private func configureButton() {
        if let button = statusItem.button {
            if #available(macOS 11.0, *) {
                button.image = NSImage(systemSymbolName: "command", accessibilityDescription: nil)
            }
            button.imagePosition = .imageOnly
        }
    }

    private func constructMenu() {
        let menu = NSMenu()

        let enableReopenItem = NSMenuItem(
            title: String(localized: "Enable Command Reopen"),
            action: #selector(toggleEnableReopen),
            keyEquivalent: ""
        )
        enableReopenItem.target = self
        enableReopenItem.state = activationMonitor.isFeatureEnabled ? .on : .off
        menu.addItem(enableReopenItem)
        self.enableReopenItem = enableReopenItem

        // Launch at Login
        let launchItem = NSMenuItem(title: String(localized: "Launch at Login"), action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchItem.target = self
        launchItem.state = launchManager.isEnabled ? .on : .off
        if #available(macOS 13.0, *) {
            // enabled
        } else {
            launchItem.isEnabled = false
        }
        menu.addItem(launchItem)

        // About
        let aboutItem = NSMenuItem(title: String(localized: "About"), action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        menu.addItem(.separator())

        // Quit
        let quitItem = NSMenuItem(title: String(localized: "Quit Command Reopen"), action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func bindMenuState() {
        activationMonitor.$isFeatureEnabled
            .receive(on: RunLoop.main)
            .sink { [weak self] isEnabled in
                self?.enableReopenItem?.state = isEnabled ? .on : .off
            }
            .store(in: &cancellables)
    }

    @objc private func toggleEnableReopen(_ sender: NSMenuItem) {
        activationMonitor.isFeatureEnabled.toggle()
        sender.state = activationMonitor.isFeatureEnabled ? .on : .off
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        let newValue = sender.state != .on
        launchManager.setEnabled(newValue)
        sender.state = launchManager.isEnabled ? .on : .off
    }

    @objc private func showAbout() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        NSApplication.shared.orderFrontStandardAboutPanel(nil)
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
