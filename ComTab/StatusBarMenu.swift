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
                NSApplication.shared.terminate(nil)
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
        let application: NSRunningApplication
        let visibleWindowBounds: [CGRect]
    }

    private enum Constants {
        static let minimumVisibleWindowDimension: CGFloat = 32
    }

    @Published private(set) var launchAtLoginEnabled: Bool

    var canHideAllWindows: Bool {
        !visibleWindowActionTargets().isEmpty
    }

    private let launchManager = LaunchAtLoginManager()

    init() {
        self.launchAtLoginEnabled = launchManager.isEnabled
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

    func openURL(_ urlString: String) {
        guard let url = URL(string: urlString) else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    private func visibleWindowActionTargets() -> [VisibleWindowActionTarget] {
        guard let windowInfoList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            AppLogger.windowActions.error("Unable to inspect on-screen windows for manual window actions.")
            return []
        }

        let runningApplicationsByPID = Dictionary(
            uniqueKeysWithValues: NSWorkspace.shared.runningApplications.map { ($0.processIdentifier, $0) }
        )
        var orderedPIDs: [pid_t] = []
        var visibleBoundsByPID: [pid_t: [CGRect]] = [:]

        for windowInfo in windowInfoList {
            guard Self.isEligibleVisibleWindow(
                windowInfo: windowInfo,
                minimumDimension: Constants.minimumVisibleWindowDimension
            ), let windowPID = ActivationMonitor.windowOwnerPID(from: windowInfo),
            let application = runningApplicationsByPID[windowPID],
            let bounds = Self.windowBounds(from: windowInfo),
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

    private static func isEligibleVisibleWindow(
        windowInfo: [String: Any],
        minimumDimension: CGFloat
    ) -> Bool {
        let ownerName = (windowInfo[kCGWindowOwnerName as String] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard ownerName?.isEmpty == false else {
            return false
        }

        let alpha = (windowInfo[kCGWindowAlpha as String] as? NSNumber)?.doubleValue
            ?? (windowInfo[kCGWindowAlpha as String] as? Double)
            ?? 1
        guard alpha > 0 else {
            return false
        }

        let layer = (windowInfo[kCGWindowLayer as String] as? NSNumber)?.intValue
            ?? (windowInfo[kCGWindowLayer as String] as? Int)
            ?? 0
        guard layer == 0 else {
            return false
        }

        guard let boundsDictionary = windowInfo[kCGWindowBounds as String] as? NSDictionary else {
            return false
        }

        var bounds = CGRect.zero
        guard CGRectMakeWithDictionaryRepresentation(boundsDictionary, &bounds) else {
            return false
        }

        return bounds.width >= minimumDimension && bounds.height >= minimumDimension
    }

    private static func windowBounds(from windowInfo: [String: Any]) -> CGRect? {
        guard let boundsDictionary = windowInfo[kCGWindowBounds as String] as? NSDictionary else {
            return nil
        }

        var bounds = CGRect.zero
        guard CGRectMakeWithDictionaryRepresentation(boundsDictionary, &bounds) else {
            return nil
        }

        return bounds
    }
}
