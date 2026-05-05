//
//  StatusBarMenu.swift
//  ComTab
//
//  Created by Codex on 2026/4/26.
//

import AppKit
import Combine
import os

@MainActor
final class StatusBarMenuController: NSObject {
    static let shared = StatusBarMenuController()

    private let statusItem: NSStatusItem
    private let model: StatusBarMenuModel
    private weak var activationMonitor: ActivationMonitor?
    private weak var accessController: AppAccessController?

    override init() {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.model = StatusBarMenuModel()
        super.init()
        configureStatusItem()
    }

    deinit {
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    func install(
        activationMonitor: ActivationMonitor,
        accessController: AppAccessController
    ) {
        self.activationMonitor = activationMonitor
        self.accessController = accessController
        updateButtonImage()
    }

    private func configureStatusItem() {
        statusItem.autosaveName = "CommandReopen.StatusItem"
        guard let button = statusItem.button else {
            return
        }
        button.target = self
        button.action = #selector(showMenu)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.toolTip = "Command Reopen"
        updateButtonImage()
    }

    private func updateButtonImage() {
        guard let button = statusItem.button else {
            return
        }
        let image = NSImage(systemSymbolName: "command", accessibilityDescription: "Command Reopen")
        image?.isTemplate = true
        button.image = image
    }

    @objc private func showMenu() {
        model.refresh()
        statusItem.showMenu(makeMenu())
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu(title: "Command Reopen")
        menu.autoenablesItems = false

        let accessController = accessController ?? .shared
        let presentation = StatusBarController.presentation(for: accessController)

        let featureItem = NSMenuItem(
            title: "Enable Command Reopen",
            action: #selector(toggleFeatureEnabled),
            keyEquivalent: ""
        )
        featureItem.target = self
        featureItem.state = activationMonitor?.isFeatureEnabled == true ? .on : .off
        featureItem.isEnabled = presentation.canToggleAutoReopen
        menu.addItem(featureItem)

        let launchItem = NSMenuItem(
            title: "Launch at Login",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        launchItem.target = self
        launchItem.state = model.launchAtLoginEnabled ? .on : .off
        menu.addItem(launchItem)

        menu.addItem(.separator())

        if presentation.showsUpgradeItem {
            let upgradeItem = NSMenuItem(
                title: "Upgrade to Pro...",
                action: #selector(showUpgradeSettings),
                keyEquivalent: ""
            )
            upgradeItem.target = self
            menu.addItem(upgradeItem)
        }

        let settingsItem = NSMenuItem(
            title: "Settings...",
            action: #selector(showSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        settingsItem.keyEquivalentModifierMask = .command
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        switch accessController.distributionChannel {
        case .appStore:
            menu.addItem(actionItem(title: "Official", action: #selector(openOfficial)))
            menu.addItem(actionItem(title: "Rate on App Store", action: #selector(openAppStoreReview)))
        case .direct:
            menu.addItem(actionItem(title: "Get on Mac App Store", action: #selector(openMacAppStore)))
            menu.addItem(actionItem(title: "GitHub", action: #selector(openGitHub)))
        }

        menu.addItem(actionItem(title: "About", action: #selector(showAbout)))

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit Command Reopen",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        quitItem.keyEquivalentModifierMask = .command
        menu.addItem(quitItem)

        return menu
    }

    private func actionItem(title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func toggleFeatureEnabled() {
        guard let activationMonitor else {
            return
        }
        let accessController = accessController ?? .shared
        guard StatusBarController.presentation(for: accessController).canToggleAutoReopen else {
            return
        }
        activationMonitor.isFeatureEnabled.toggle()
    }

    @objc private func toggleLaunchAtLogin() {
        model.setLaunchAtLogin(!model.launchAtLoginEnabled)
    }

    @objc private func showUpgradeSettings() {
        SettingsOpener.shared.open(
            initialTab: .about,
            presentsPaywall: true
        )
    }

    @objc private func showSettings() {
        SettingsOpener.shared.open()
    }

    @objc private func openOfficial() {
        model.openURL(ExternalLinks.officialURL)
    }

    @objc private func openAppStoreReview() {
        model.openURL(AppStoreLinks.reviewURL)
    }

    @objc private func openMacAppStore() {
        model.openURL(AppStoreLinks.productURL)
    }

    @objc private func openGitHub() {
        model.openURL(ExternalLinks.githubURL)
    }

    @objc private func showAbout() {
        model.showAbout(distributionChannel: (accessController ?? .shared).distributionChannel)
    }

    @objc private func quit() {
        model.quit()
    }
}

private extension NSStatusItem {
    func showMenu(_ menu: NSMenu) {
        let originalMenu = self.menu
        defer {
            self.menu = originalMenu
        }
        self.menu = menu
        button?.performClick(nil)
    }
}

@MainActor
final class StatusBarMenuModel: ObservableObject {
    @Published private(set) var launchAtLoginEnabled: Bool

    private let launchManager: LaunchAtLoginManaging
    private let urlOpener: URLOpening
    private let applicationPresenter: ApplicationPresenting

    init(
        launchManager: LaunchAtLoginManaging? = nil,
        urlOpener: URLOpening? = nil,
        applicationPresenter: ApplicationPresenting? = nil
    ) {
        let resolvedLaunchManager = launchManager ?? LaunchAtLoginManager()
        self.launchManager = resolvedLaunchManager
        self.urlOpener = urlOpener ?? WorkspaceURLOpener()
        self.applicationPresenter = applicationPresenter ?? SharedApplicationPresenter()
        self.launchAtLoginEnabled = resolvedLaunchManager.isEnabled
    }

    func refresh() {
        launchAtLoginEnabled = launchManager.isEnabled
    }

    func setLaunchAtLogin(_ isEnabled: Bool) {
        launchManager.setEnabled(isEnabled)
        launchAtLoginEnabled = launchManager.isEnabled
    }

    func showAbout(distributionChannel: DistributionChannel) {
        applicationPresenter.showAbout(distributionChannel: distributionChannel)
    }

    func openURL(_ urlString: String) {
        guard let url = URL(string: urlString) else {
            return
        }

        urlOpener.open(url)
    }

    func quit() {
        applicationPresenter.terminate()
    }
}
