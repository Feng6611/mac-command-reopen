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
            Section {
                Picker(selection: $appLanguage.selected) {
                    ForEach(SupportedLanguage.allCases) { language in
                        // Native-language labels so users can always find their own language,
                        // regardless of the current UI language.
                        Text(verbatim: language.displayName).tag(language)
                    }
                } label: {
                    Text("Language")
                }
            }

            Section {
                Toggle("Enable Command Reopen", isOn: activationMonitor.featureToggleBinding)
                    .disabled(isFeatureLocked)
                Toggle("Launch at Login", isOn: launchAtLoginManager.binding)
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

    var body: some View {
        Section {
            if bundleIDs.isEmpty {
                Text("No excluded apps")
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

            LabeledContent("Add") {
                ApplicationSearchControl(
                    query: $query,
                    results: searchResults,
                    excludedBundleIDs: excludedBundleIDs,
                    isDisabled: isDisabled,
                    addAction: addApplicationAction
                )
            }
        } header: {
            Text("Excluded Apps")
        } footer: {
            Text("Excluded apps keep the standard Cmd+Tab behavior.")
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

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            TextField("", text: $query, prompt: Text("App name or bundle ID"))
                .textFieldStyle(.roundedBorder)
                .disabled(isDisabled)
                .accessibilityLabel("App name or bundle ID")
                .onSubmit(addFirstAvailableResult)

            if !trimmedQuery.isEmpty {
                if results.isEmpty {
                    Text("No matching apps found.")
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

    var body: some View {
        HStack(spacing: DS.Spacing.sm) {
            ApplicationInfoLabel(applicationInfo: applicationInfo)

            Spacer(minLength: DS.Spacing.sm)

            Button(isAlreadyExcluded ? "Added" : "Add") {
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
