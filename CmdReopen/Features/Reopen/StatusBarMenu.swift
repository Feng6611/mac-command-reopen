//
//  StatusBarMenu.swift
//  CmdReopen
//
//  Created by Codex on 2026/4/26.
//

import AppKit
import Combine
import KikiMenuBar
import os

@MainActor
final class StatusBarMenuController {
    static let shared = StatusBarMenuController()

    /// Never localized — it is the product name, and it also fills the `%@` in
    /// the shared `Quit %@` menu string.
    private static let appDisplayName = "Command Reopen"

    private var menuBarController: KikiMenuBarController?
    private let model = StatusBarMenuModel(reviewPromptRequester: { trigger in
        _ = ReopenStatsStore.shared.requestReviewIfEligible(for: trigger)
    })
    private weak var activationMonitor: ActivationMonitor?
    private weak var accessController: AppAccessController?

    func install(
        activationMonitor: ActivationMonitor,
        accessController: AppAccessController
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
    }

    private func makeItems() -> [KikiMenuItem] {
        model.refresh()

        let accessController = accessController ?? .shared
        let presentation = StatusBarController.presentation(for: accessController)

        var items: [KikiMenuItem] = [
            .toggle(
                title: AppLanguage.shared.string("Enable Command Reopen"),
                isOn: activationMonitor?.isFeatureEnabled == true,
                isEnabled: presentation.canToggleAutoReopen,
                action: { [weak self] in
                    self?.toggleFeatureEnabled()
                }
            ),
            .toggle(
                title: AppLanguage.shared.string("Launch at Login"),
                isOn: model.launchAtLoginEnabled,
                action: { [weak self] in
                    guard let model = self?.model else { return }
                    model.setLaunchAtLogin(!model.launchAtLoginEnabled)
                }
            ),
            .separator
        ]

        items.append(
            .action(title: model.statisticsItemTitle, badgeCount: model.statisticsBadgeCount) {
                SettingsOpener.shared.open(initialTab: .statistics)
            }
        )

        items.append(.settings(title: AppLanguage.shared.string("Settings…")) {
            SettingsOpener.shared.open()
        })

        if presentation.showsUpgradeItem {
            items.append(.action(title: AppLanguage.shared.string("Upgrade to Pro…")) {
                SettingsOpener.shared.open(
                    initialTab: .about,
                    presentsPaywall: true,
                    paywallSource: .statusBar
                )
            })
        }
        items.append(.separator)

        switch accessController.distributionChannel {
        case .appStore:
            items.append(.action(title: AppLanguage.shared.string("Rate on App Store")) { [weak self] in
                self?.model.openURL(AppStoreLinks.reviewURL)
            })
        case .direct:
            items.append(.action(title: AppLanguage.shared.string("Get on Mac App Store")) { [weak self] in
                self?.model.openURL(AppStoreLinks.productURL)
            })
        }

        items.append(.about(title: AppLanguage.shared.string("About")) { [weak self] in
            guard let self else { return }
            self.model.showAbout(
                distributionChannel: (self.accessController ?? .shared).distributionChannel
            )
        })
        items.append(.separator)
        // Built from Kiki's `Quit %@` key rather than a literal "Quit Command
        // Reopen", so this item uses the same translations as every other Kiki
        // menu bar app.
        let quitTitle = AppLanguage.shared.string(
            localized: "Quit \(Self.appDisplayName)",
            comment: "Menu item. %@ is the app display name."
        )
        items.append(.action(title: quitTitle, shortcut: .quit) { [weak self] in
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
    /// Below this the count is too small to be worth stating, and a menu is the
    /// wrong place to tell someone the app has barely done anything.
    static let minimumReopensForMenuCount = 10

    @Published private(set) var launchAtLoginEnabled: Bool
    @Published private(set) var totalReopens: Int

    private let launchManager: LaunchAtLoginManaging
    private let urlOpener: URLOpening
    private let applicationPresenter: ApplicationPresenting
    private let reviewPromptRequester: (ReviewPromptTrigger) -> Void
    private let totalReopensProvider: () -> Int

    /// Carries the running total on the item that leads to the full breakdown,
    /// rather than as a line of its own: a number nobody can act on takes the
    /// most prominent slot in the menu and leaves the curiosity it creates
    /// nowhere to go. The lifetime total is used rather than today's, which
    /// reads as 0 or 1 on a quiet morning.
    ///
    /// From macOS 14 the count is a trailing menu badge, which is both the
    /// system treatment and the reading order we want — the label, then the
    /// number sitting alone against the right edge. On macOS 13 there is no
    /// badge, so it falls back into the title.
    var statisticsItemTitle: String {
        guard showsReopenCount, statisticsBadgeCount == nil else {
            return AppLanguage.shared.string("Statistics")
        }
        return AppLanguage.shared.string(
            localized: "Statistics — \(totalReopens.formatted()) restored",
            comment: "Menu item opening the stats pane on macOS 13, where a menu badge is unavailable."
        )
    }

    var statisticsBadgeCount: Int? {
        guard showsReopenCount, #available(macOS 14.0, *) else {
            return nil
        }
        return totalReopens
    }

    private var showsReopenCount: Bool {
        totalReopens >= Self.minimumReopensForMenuCount
    }

    init(
        launchManager: LaunchAtLoginManaging? = nil,
        urlOpener: URLOpening? = nil,
        applicationPresenter: ApplicationPresenting? = nil,
        reviewPromptRequester: @escaping (ReviewPromptTrigger) -> Void,
        totalReopensProvider: (() -> Int)? = nil
    ) {
        let resolvedLaunchManager = launchManager ?? LaunchAtLoginManager()
        let resolvedTotalReopensProvider = totalReopensProvider ?? {
            ReopenStatsStore.shared.totalSuccessfulReopens
        }
        self.launchManager = resolvedLaunchManager
        self.urlOpener = urlOpener ?? WorkspaceURLOpener()
        self.applicationPresenter = applicationPresenter ?? SharedApplicationPresenter()
        self.reviewPromptRequester = reviewPromptRequester
        self.totalReopensProvider = resolvedTotalReopensProvider
        self.launchAtLoginEnabled = resolvedLaunchManager.isEnabled
        self.totalReopens = resolvedTotalReopensProvider()
    }

    func refresh() {
        launchAtLoginEnabled = launchManager.isEnabled
        totalReopens = totalReopensProvider()
    }

    func setLaunchAtLogin(_ isEnabled: Bool) {
        let wasEnabled = launchAtLoginEnabled
        launchManager.setEnabled(isEnabled)
        launchAtLoginEnabled = launchManager.isEnabled
        if !wasEnabled, launchAtLoginEnabled {
            reviewPromptRequester(.launchAtLoginEnabled)
        }
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
