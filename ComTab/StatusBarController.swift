//
//  StatusBarController.swift
//  Command Reopen
//
//  Created by CHEN on 2025/10/31.
//

import AppKit
import Combine

@MainActor
final class StatusBarController: NSObject {
    private let statusItem: NSStatusItem
    private let activationMonitor: ActivationMonitor
    private let launchManager = LaunchAtLoginManager()
    private let distributionChannel = DistributionChannel.current
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

        menu.addItem(.separator())
        menu.addItem(makeMenuItem(title: String(localized: "Settings…"), action: #selector(showSettings)))
        menu.addItem(.separator())

        switch distributionChannel {
        case .appStore:
            menu.addItem(makeMenuItem(title: String(localized: "Official"), action: #selector(openOfficialWebsite)))
            menu.addItem(makeMenuItem(title: String(localized: "Rate on App Store"), action: #selector(openAppStoreReview)))
        case .direct:
            menu.addItem(makeMenuItem(title: String(localized: "Get on Mac App Store"), action: #selector(openMacAppStore)))
            menu.addItem(makeMenuItem(title: String(localized: "GitHub"), action: #selector(openGitHub)))
        }

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

    private func makeMenuItem(title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
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
        switch distributionChannel {
        case .appStore:
            NSApplication.shared.orderFrontStandardAboutPanel(options: [
                .credits: NSAttributedString(string: "Contact: \(ExternalLinks.contactEmailAddress)")
            ])
        case .direct:
            NSApplication.shared.orderFrontStandardAboutPanel(nil)
        }
    }

    @objc private func showSettings() {
        SettingsWindowController.shared.show(activationMonitor: activationMonitor)
    }

    @objc private func openOfficialWebsite() {
        openURL(ExternalLinks.officialURL)
    }

    @objc private func openAppStoreReview() {
        openURL(AppStoreLinks.reviewURL)
    }

    @objc private func openMacAppStore() {
        openURL(AppStoreLinks.productURL)
    }

    @objc private func openGitHub() {
        openURL(ExternalLinks.githubURL)
    }

    private func openURL(_ urlString: String) {
        guard let url = URL(string: urlString) else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
