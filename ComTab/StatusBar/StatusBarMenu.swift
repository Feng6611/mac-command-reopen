//
//  StatusBarMenu.swift
//  ComTab
//
//  Created by Codex on 2026/4/26.
//

import AppKit
import Combine
import CoreGraphics
import SwiftUI
import os

struct StatusBarMenu: View {
    @EnvironmentObject private var activationMonitor: ActivationMonitor
    @EnvironmentObject private var accessController: AppAccessController
    @StateObject private var model = StatusBarMenuModel()

    var body: some View {
        let presentation = StatusBarController.presentation(for: accessController)

        Group {
            Toggle(isOn: featureEnabledBinding(canToggle: presentation.canToggleAutoReopen)) {
                Text("Enable Command Reopen")
            }
            .disabled(!presentation.canToggleAutoReopen)

            Toggle(isOn: launchAtLoginBinding) {
                Text("Launch at Login")
            }

            Divider()

            Button("Hide All Windows") {
                model.hideAllWindows()
            }
            .disabled(!model.canHideAllWindows)

            Divider()

            if presentation.showsUpgradeItem {
                proSettingsItem
            }

            settingsItem

            Divider()

            switch accessController.distributionChannel {
            case .appStore:
                Button("Official") {
                    model.openURL(ExternalLinks.officialURL)
                }

                Button("Rate on App Store") {
                    model.openURL(AppStoreLinks.reviewURL)
                }
            case .direct:
                Button("Get on Mac App Store") {
                    model.openURL(AppStoreLinks.productURL)
                }

                Button("GitHub") {
                    model.openURL(ExternalLinks.githubURL)
                }
            }

            Button("About") {
                model.showAbout(distributionChannel: accessController.distributionChannel)
            }

            Divider()

            Button("Quit Command Reopen") {
                model.quit()
            }
            .keyboardShortcut("q")
        }
        .onAppear {
            model.refresh()
        }
    }

    private func featureEnabledBinding(canToggle: Bool) -> Binding<Bool> {
        Binding {
            activationMonitor.isFeatureEnabled
        } set: { isEnabled in
            guard canToggle else {
                return
            }

            activationMonitor.isFeatureEnabled = isEnabled
        }
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding {
            model.launchAtLoginEnabled
        } set: { isEnabled in
            model.setLaunchAtLogin(isEnabled)
        }
    }

    @ViewBuilder
    private var proSettingsItem: some View {
        if #available(macOS 14.0, *) {
            SettingsLink {
                Text("Upgrade to Pro...")
            }
            .simultaneousGesture(
                TapGesture().onEnded {
                    SettingsWindowController.shared.prepareForSettingsScene(
                        accessController: accessController,
                        initialTab: .pro
                    )
                }
            )
        } else {
            Button("Upgrade to Pro...") {
                SettingsWindowController.shared.show(
                    activationMonitor: activationMonitor,
                    accessController: accessController,
                    initialTab: .pro
                )
            }
        }
    }

    @ViewBuilder
    private var settingsItem: some View {
        if #available(macOS 14.0, *) {
            SettingsLink()
                .simultaneousGesture(
                    TapGesture().onEnded {
                        SettingsWindowController.shared.prepareForSettingsScene(accessController: accessController)
                    }
                )
        } else {
            Button("Settings...") {
                SettingsWindowController.shared.show(
                    activationMonitor: activationMonitor,
                    accessController: accessController
                )
            }
        }
    }
}

@MainActor
final class StatusBarMenuModel: ObservableObject {
    private struct VisibleWindowActionTarget {
        let application: WindowActionApplication
        let visibleWindowBounds: [CGRect]
    }

    @Published private(set) var launchAtLoginEnabled: Bool

    var canHideAllWindows: Bool {
        !visibleWindowActionTargets().isEmpty
    }

    private let launchManager: LaunchAtLoginManaging
    private let windowInfoProvider: WindowInfoListing
    private let applicationProvider: WindowActionApplicationProviding
    private let urlOpener: URLOpening
    private let applicationPresenter: ApplicationPresenting

    init(
        launchManager: LaunchAtLoginManaging? = nil,
        windowInfoProvider: WindowInfoListing? = nil,
        applicationProvider: WindowActionApplicationProviding? = nil,
        urlOpener: URLOpening? = nil,
        applicationPresenter: ApplicationPresenting? = nil
    ) {
        let resolvedLaunchManager = launchManager ?? LaunchAtLoginManager()
        self.launchManager = resolvedLaunchManager
        self.windowInfoProvider = windowInfoProvider ?? CoreGraphicsWindowInfoProvider()
        self.applicationProvider = applicationProvider ?? WorkspaceWindowActionApplicationProvider()
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

    func hideAllWindows() {
        let targetApplications = visibleWindowActionTargets()
        guard !targetApplications.isEmpty else {
            AppLogger.windowActions.info("Hide All Windows ignored because there are no eligible visible apps.")
            return
        }

        AppLogger.windowActions.notice("Hiding \(targetApplications.count) visible apps on the current desktop.")
        for target in targetApplications {
            let bundleID = target.application.bundleIdentifier ?? "unknown app"
            if target.application.hide() {
                AppLogger.windowActions.debug("Hide All Windows sent to \(bundleID).")
            } else {
                AppLogger.windowActions.error("Hide All Windows failed for \(bundleID).")
            }
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

    private func visibleWindowActionTargets() -> [VisibleWindowActionTarget] {
        guard let windowInfoList = windowInfoProvider.onScreenWindowInfo() else {
            AppLogger.windowActions.error("Unable to inspect on-screen windows for manual window actions.")
            return []
        }

        let runningApplicationsByPID = Dictionary(
            uniqueKeysWithValues: applicationProvider.runningWindowActionApplications.map { ($0.processIdentifier, $0) }
        )
        var orderedPIDs: [pid_t] = []
        var visibleBoundsByPID: [pid_t: [CGRect]] = [:]

        for windowInfo in windowInfoList {
            guard let windowPID = WindowInspector.windowOwnerPID(from: windowInfo),
            let application = runningApplicationsByPID[windowPID],
            WindowInspector.hasVisibleWindow(ownerPID: windowPID, windowInfoList: [windowInfo]),
            let bounds = WindowInspector.windowBounds(from: windowInfo),
            StatusBarController.canPerformManualWindowAction(
                frontmostBundleID: application.bundleIdentifier,
                isTerminated: application.isTerminated
            ) else {
                continue
            }

            if visibleBoundsByPID[windowPID] == nil {
                orderedPIDs.append(windowPID)
                visibleBoundsByPID[windowPID] = []
            }
            visibleBoundsByPID[windowPID, default: []].append(bounds)
        }

        return orderedPIDs.compactMap { pid in
            guard let application = runningApplicationsByPID[pid],
                  let visibleWindowBounds = visibleBoundsByPID[pid],
                  !visibleWindowBounds.isEmpty else {
                return nil
            }

            return VisibleWindowActionTarget(
                application: application,
                visibleWindowBounds: visibleWindowBounds
            )
        }
    }
}
