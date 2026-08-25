//
//  SettingsView.swift
//  CmdReopen
//
//  Created by Codex on 2026/3/28.
//

import AppKit
import Combine
import KikiSettings
import SwiftUI

// MARK: - Settings Tab Content

struct SettingsTabContent: View {
    @EnvironmentObject private var activationMonitor: ActivationMonitor
    @EnvironmentObject private var accessController: AppAccessController
    @EnvironmentObject private var appLanguage: AppLanguage
    @ObservedObject private var route = SettingsNavigationModel.shared
#if APPSTORE
    @ObservedObject private var accessModel = CommandAccessModel.shared
#endif

    private let appLookupProvider = ApplicationLookupProvider()

    @StateObject private var launchAtLoginManager = LaunchAtLoginManager()
    @State private var appLookupQuery = ""
    @State private var applicationCatalog: [ExcludedApplicationInfo] = []

    private var isFeatureLocked: Bool {
        !accessController.isCoreFeatureAvailable
    }

    private var appLookupResults: [ExcludedApplicationInfo] {
        appLookupProvider.search(query: appLookupQuery, in: applicationCatalog)
    }

    var body: some View {
        KikiSettingsPane {
            // A disabled toggle with no reason is a dead end: when the trial
            // has ended the controls below dim, so this row is the one place
            // that names why and offers the way out. Absent in the free build,
            // where the feature never locks.
            if isFeatureLocked {
                Section {
                    lockedBanner
                }
            }

            Section {
                KikiSettingsMenuPickerRow(
                    appLanguage.string("Language"),
                    selection: $appLanguage.selected,
                    options: SupportedLanguage.allCases,
                    systemImage: "globe",
                    // Native-language labels so users can always find their own
                    // language regardless of the current UI language.
                    optionTitle: { $0.displayName }
                )

                // The binding reports a registration that macOS is holding for
                // approval; without it the switch slides back on its own.
                KikiSettingsToggleRow(
                    appLanguage.string("Launch at Login"),
                    isOn: launchAtLoginManager.binding,
                    systemImage: "power"
                )
                .onChange(of: launchAtLoginManager.isEnabled) { isEnabled in
                    guard isEnabled else { return }
                    _ = ReopenStatsStore.shared.requestReviewIfEligible(for: .launchAtLoginEnabled)
                }
            }

            ExcludedAppsSection(
                bundleIDs: activationMonitor.sortedUserExcludedBundleIDs,
                isDisabled: isFeatureLocked,
                removeAction: removeExcludedBundleID,
                query: $appLookupQuery,
                searchResults: appLookupResults,
                excludedBundleIDs: activationMonitor.userExcludedBundleIDs,
                addApplicationAction: addLookupResult
            )
            .opacity(isFeatureLocked ? 0.5 : 1)

            Section {
                Button {
                    route.presentMacShortcuts()
                } label: {
                    KikiSettingsValueRow(
                        appLanguage.string("Mac window shortcuts"),
                        systemImage: "keyboard"
                    ) {
                        Text("Nine of them, and where this app fits")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .onChange(of: appLanguage.selected) { _ in
            SettingsWindowController.shared.refreshLocalizedTabs()
        }
        .task {
            await Task.yield()
            refreshApplicationCatalog()
            clearInitialFocus()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didLaunchApplicationNotification)) { _ in
            refreshApplicationCatalog()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didTerminateApplicationNotification)) { _ in
            refreshApplicationCatalog()
        }
    }

    /// Reuses the About pane's expired-state wording so the two surfaces name
    /// the same thing the same way. The whole row is the upgrade affordance —
    /// the paywall sheet lives on the App Store build, the only build that can
    /// reach a locked state.
    private var lockedBanner: some View {
        Button {
            route.presentPaywall()
        } label: {
            HStack(spacing: DS.Spacing.sm) {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(DS.Colors.brandPrimary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(appLanguage.string("Trial ended"))
                        .font(.callout.weight(.medium))
                    Text(appLanguage.string("Upgrade to continue automatic window reopening."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: DS.Spacing.sm)

                Text(appLanguage.string("Upgrade"))
                    .font(.callout.weight(.medium))
                    .foregroundStyle(DS.Colors.brandPrimary)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func addLookupResult(_ result: ExcludedApplicationInfo) {
        guard !activationMonitor.userExcludedBundleIDs.contains(result.bundleID) else {
            return
        }

        activationMonitor.addExcludedBundleID(result.bundleID)
        appLookupQuery = ""
        refreshApplicationCatalog()
    }

    private func removeExcludedBundleID(_ bundleID: String) {
        activationMonitor.removeExcludedBundleID(bundleID)
        refreshApplicationCatalog()
    }

    private func refreshApplicationCatalog() {
        let selfBundleID = Bundle.main.bundleIdentifier

        let userApps = NSWorkspace.shared.runningApplications
            .filter { app in
                guard app.activationPolicy == .regular,
                      let bundleID = app.bundleIdentifier else {
                    return false
                }
                return bundleID != selfBundleID
            }

        applicationCatalog = appLookupProvider.applicationCatalog(runningApplications: userApps)
    }

    private func clearInitialFocus() {
        DispatchQueue.main.async {
            NSApp.keyWindow?.makeFirstResponder(nil)
        }
    }

}

/// The exclusion list and the control that adds to it are one feature, so they
/// share one section: the search field is how this list grows, not a separate
/// setting. Adding sits below the list, where a "+" control sits in the system
/// settings panes this pane imitates.
private struct ExcludedAppsSection: View {
    let bundleIDs: [String]
    let isDisabled: Bool
    let removeAction: (String) -> Void

    @Binding var query: String
    let searchResults: [ExcludedApplicationInfo]
    let excludedBundleIDs: Set<String>
    let addApplicationAction: (ExcludedApplicationInfo) -> Void

    @ObservedObject private var appLanguage = AppLanguage.shared

    var body: some View {
        Section {
            if bundleIDs.isEmpty {
                Text(appLanguage.string("No excluded apps"))
                    .foregroundColor(.secondary)
            } else {
                ForEach(bundleIDs, id: \.self) { bundleID in
                    ExcludedApplicationRow(
                        bundleID: bundleID,
                        isDisabled: isDisabled,
                        removeAction: removeAction
                    )
                }
            }

            LabeledContent(appLanguage.string("Add App")) {
                ApplicationSearchControl(
                    query: $query,
                    results: searchResults,
                    excludedBundleIDs: excludedBundleIDs,
                    isDisabled: isDisabled,
                    addAction: addApplicationAction
                )
            }
        } header: {
            Text(appLanguage.string("Excluded Apps"))
        } footer: {
            Text(appLanguage.string("Excluded apps keep the standard Cmd+Tab behavior."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct ExcludedApplicationRow: View {
    let bundleID: String
    let isDisabled: Bool
    let removeAction: (String) -> Void

    private var applicationInfo: ExcludedApplicationInfo {
        ExcludedApplicationInfo(bundleID: bundleID)
    }

    var body: some View {
        HStack(spacing: DS.Spacing.sm) {
            ApplicationInfoLabel(applicationInfo: applicationInfo)

            Spacer(minLength: 0)

            Button {
                removeAction(bundleID)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .disabled(isDisabled)
            .help("Remove \(applicationInfo.displayName)")
            .accessibilityLabel("Remove \(applicationInfo.displayName)")
        }
    }
}

private struct ApplicationSearchControl: View {
    @Binding var query: String
    let results: [ExcludedApplicationInfo]
    let excludedBundleIDs: Set<String>
    let isDisabled: Bool
    let addAction: (ExcludedApplicationInfo) -> Void

    @ObservedObject private var appLanguage = AppLanguage.shared

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            TextField("", text: $query, prompt: Text(appLanguage.string("Search App name or bundle ID…")))
                .textFieldStyle(.roundedBorder)
                .disabled(isDisabled)
                .accessibilityLabel(appLanguage.string("Search App name or bundle ID…"))
                .onSubmit(addFirstAvailableResult)

            if !trimmedQuery.isEmpty {
                if results.isEmpty {
                    Text(appLanguage.string("No matching apps found."))
                        .kikiSettingDescription()
                } else {
                    VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                        ForEach(results) { result in
                            ApplicationSearchResultRow(
                                applicationInfo: result,
                                isAlreadyExcluded: excludedBundleIDs.contains(result.bundleID),
                                isDisabled: isDisabled,
                                addAction: addAction
                            )
                        }
                    }
                }
            }
        }
    }

    private func addFirstAvailableResult() {
        guard let result = results.first(where: { !excludedBundleIDs.contains($0.bundleID) }) else {
            return
        }
        addAction(result)
    }
}

private struct ApplicationSearchResultRow: View {
    let applicationInfo: ExcludedApplicationInfo
    let isAlreadyExcluded: Bool
    let isDisabled: Bool
    let addAction: (ExcludedApplicationInfo) -> Void

    @ObservedObject private var appLanguage = AppLanguage.shared

    var body: some View {
        HStack(spacing: DS.Spacing.sm) {
            ApplicationInfoLabel(applicationInfo: applicationInfo)

            Spacer(minLength: DS.Spacing.sm)

            Button(isAlreadyExcluded ? appLanguage.string("Added") : appLanguage.string("Add")) {
                addAction(applicationInfo)
            }
            .disabled(isAlreadyExcluded || isDisabled)
        }
        .padding(.vertical, DS.Spacing.xxs)
    }
}

private struct ApplicationInfoLabel: View {
    let applicationInfo: ExcludedApplicationInfo

    var body: some View {
        HStack(spacing: DS.Spacing.sm) {
            applicationIcon

            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(applicationInfo.displayName)
                    .lineLimit(1)

                Text(applicationInfo.bundleID)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .textSelection(.enabled)
            }
        }
    }

    @ViewBuilder
    private var applicationIcon: some View {
        if let applicationURL = applicationInfo.applicationURL {
            Image(nsImage: NSWorkspace.shared.icon(forFile: applicationURL.path))
                .resizable()
                .frame(width: 20, height: 20)
        } else {
            Image(systemName: "app")
                .frame(width: 20, height: 20)
                .foregroundStyle(.secondary)
        }
    }
}
