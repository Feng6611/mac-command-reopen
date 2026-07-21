//
//  StatusBarMenu.swift
//  CmdReopen
//
//  Created by Codex on 2026/4/26.
//

import AppKit
import Combine
import Defaults
import KikiMenuBar
import os

@MainActor
final class StatusBarMenuController {
    static let shared = StatusBarMenuController()

    private var menuBarController: KikiMenuBarController?
    private let model = StatusBarMenuModel()
    private let defaults: UserDefaults
    private var statsCancellable: AnyCancellable?
    private weak var activationMonitor: ActivationMonitor?
    private weak var accessController: AppAccessController?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func install(
        activationMonitor: ActivationMonitor,
        accessController: AppAccessController,
        reopenStatsStore: ReopenStatsStore
    ) {
        self.activationMonitor = activationMonitor
        self.accessController = accessController

        guard menuBarController == nil else {
            return
        }

        menuBarController = KikiMenuBarController(
            title: "Command Reopen",
            autosaveName: "CommandReopen.StatusItem",
            systemImageName: "command",
            accessibilityDescription: "Command Reopen",
            tooltip: "Command Reopen"
        ) { [weak self] in
            self?.makeItems() ?? []
        }

        statsCancellable = reopenStatsStore.$snapshot
            .map { snapshot in
                snapshot.dailyCounts[ReopenStatsStore.dayKeyFormatter.string(from: Date())] ?? 0
            }
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] todayCount in
                self?.handleSuccessfulReopenRecorded(todayCount: todayCount)
            }
    }

    private func handleSuccessfulReopenRecorded(todayCount: Int) {
        guard defaults[AppDefaults.menuBarPulseEnabled] else {
            return
        }
        guard ReopenStatsStore.shouldPulseMenuBarIcon(todayCount: todayCount) else {
            return
        }
        menuBarController?.pulseButton()
    }

    private func makeItems() -> [KikiMenuItem] {
        model.refresh()

        let accessController = accessController ?? .shared
        let presentation = StatusBarController.presentation(for: accessController)

        var items: [KikiMenuItem] = [
            .toggle(
                title: "Enable Command Reopen",
                isOn: activationMonitor?.isFeatureEnabled == true,
                isEnabled: presentation.canToggleAutoReopen,
                action: { [weak self] in
                    self?.toggleFeatureEnabled()
                }
            ),
            .toggle(
                title: "Launch at Login",
                isOn: model.launchAtLoginEnabled,
                action: { [weak self] in
                    guard let model = self?.model else { return }
                    model.setLaunchAtLogin(!model.launchAtLoginEnabled)
                }
            ),
            .separator
        ]

        if presentation.showsUpgradeItem {
            items.append(.action(title: "Upgrade to Pro...") {
                SettingsOpener.shared.open(
                    initialTab: .about,
                    presentsPaywall: true
                )
            })
        }

        items.append(.settings(title: "Settings...") {
            SettingsOpener.shared.open()
        })
        items.append(.separator)

        switch accessController.distributionChannel {
        case .appStore:
            items.append(.action(title: "Official") { [weak self] in
                self?.model.openURL(ExternalLinks.officialURL)
            })
            items.append(.action(title: "Rate on App Store") { [weak self] in
                self?.model.openURL(AppStoreLinks.reviewURL)
            })
        case .direct:
            items.append(.action(title: "Get on Mac App Store") { [weak self] in
                self?.model.openURL(AppStoreLinks.productURL)
            })
            items.append(.action(title: "GitHub") { [weak self] in
                self?.model.openURL(ExternalLinks.githubURL)
            })
        }

        items.append(.about(title: "About") { [weak self] in
            guard let self else { return }
            self.model.showAbout(
                distributionChannel: (self.accessController ?? .shared).distributionChannel
            )
        })
        items.append(.separator)
        items.append(.quit(appName: "Command Reopen") { [weak self] in
            self?.model.quit()
        })

        return items
    }

    private func toggleFeatureEnabled() {
        guard let activationMonitor else {
            return
        }
        let accessController = accessController ?? .shared
        guard StatusBarController.presentation(for: accessController).canToggleAutoReopen else {
            return
        }
        activationMonitor.isFeatureEnabled.toggle()
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
