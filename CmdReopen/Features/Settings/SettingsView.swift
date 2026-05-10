//
//  SettingsView.swift
//  CmdReopen
//
//  Created by Codex on 2026/3/28.
//

import AppKit
import Combine
import LaunchAtLogin
#if APPSTORE
import RevenueCatCommerceKit
#endif
import SwiftUI

// MARK: - Settings Tab

enum SettingsTab: Int, CaseIterable {
    case general
    case statistics
    case about

    static func visibleTabs(showProTab: Bool) -> [SettingsTab] {
        [.general, .statistics, .about]
    }

    func title(for distributionChannel: DistributionChannel) -> String {
        switch self {
        case .general: return "General"
        case .statistics: return "Stats"
        case .about: return "About"
        }
    }

    func icon(for distributionChannel: DistributionChannel) -> String {
        switch self {
        case .general: return "gearshape"
        case .statistics: return "chart.bar.xaxis"
        case .about: return "info.circle"
        }
    }

}

// MARK: - Main Settings View

struct SettingsView: View {
    @EnvironmentObject private var accessController: AppAccessController
    @EnvironmentObject private var navigationModel: SettingsNavigationModel

    var body: some View {
        TabView(selection: selectedTabBinding) {
            SettingsTabContent()
                .settingsTabPane()
                .tabItem { tabLabel(for: .general) }
                .tag(SettingsTab.general)

            LazySettingsTabContent(tab: .statistics) {
                ReopenStatsView()
            }
                .tabItem { tabLabel(for: .statistics) }
                .tag(SettingsTab.statistics)

            LazySettingsTabContent(tab: .about) {
#if APPSTORE
                AppStoreAboutTabContent()
#else
                AboutTabContent()
#endif
            }
                .tabItem { tabLabel(for: .about) }
                .tag(SettingsTab.about)
        }
        .frame(width: DS.Window.settingsWidth, height: DS.Window.settingsHeight)
    }

    private var selectedTabBinding: Binding<SettingsTab?> {
        Binding(
            get: { navigationModel.selectedTab },
            set: { newValue in
                if let newValue {
                    navigationModel.selectedTab = newValue
                }
            }
        )
    }

    private func tabLabel(for tab: SettingsTab) -> Label<Text, Image> {
        Label(
            tab.title(for: accessController.distributionChannel),
            systemImage: tab.icon(for: accessController.distributionChannel)
        )
    }
}

private struct LazySettingsTabContent<Content: View>: View {
    @EnvironmentObject private var navigationModel: SettingsNavigationModel

    let tab: SettingsTab
    @ViewBuilder var content: () -> Content

    var body: some View {
        if navigationModel.selectedTab == tab {
            content()
        } else {
            Color.clear
        }
    }
}

#if APPSTORE
private struct AppStoreAboutTabContent: View {
    @StateObject private var proStatusManager = ProStatusManager.shared

    var body: some View {
        AboutTabContent()
            .environmentObject(proStatusManager)
    }
}
#endif

private extension View {
    func settingsTabPane() -> some View {
        self
            .scenePadding()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

// MARK: - About Tab Content

struct AboutTabContent: View {
    @EnvironmentObject private var accessController: AppAccessController
    @EnvironmentObject private var navigationModel: SettingsNavigationModel
#if APPSTORE
    @EnvironmentObject private var proStatusManager: ProStatusManager
    @State private var previewMode: ProPreviewMode = .live
#endif

    var body: some View {
        Form {
            Section {
                appIdentity
                    .padding(.vertical, DS.Spacing.xl)
                    .listRowBackground(AboutColors.background)
            }

            Section {
                statusRow

#if APPSTORE
                if accessController.distributionChannel == .appStore,
                   showsManageSubscriptions {
                    AboutLinkRow(
                        title: "Manage Subscriptions",
                        value: "App Store",
                        urlString: AppStoreLinks.manageSubscriptionsURL,
                        systemImage: "creditcard"
                    )
                }
#endif
            }
            .listRowBackground(AboutColors.sectionBackground)

            Section {
                AboutLinkRow(
                    title: "Official",
                    value: "commandreopen.com",
                    urlString: ExternalLinks.officialURL,
                    systemImage: "globe"
                )
                AboutLinkRow(
                    title: "Email",
                    value: ExternalLinks.contactEmailAddress,
                    systemImage: "envelope",
                    trailingSystemImage: "doc.on.doc",
                    action: copyContactEmail
                )
                AboutLinkRow(
                    title: "GitHub",
                    value: "GitHub",
                    urlString: ExternalLinks.githubURL,
                    systemImage: "chevron.left.forwardslash.chevron.right"
                )
            }
            .listRowBackground(AboutColors.sectionBackground)

#if DEBUG && APPSTORE
            Section {
                Picker("UI Preview", selection: $previewMode) {
                    ForEach(ProPreviewMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Button {
                    OnboardingWindowController.shared.show(proStatusManager: proStatusManager)
                } label: {
                    Label("Trigger Onboarding", systemImage: "sparkles")
                }
                .buttonStyle(.link)
            }
            .listRowBackground(AboutColors.sectionBackground)
#endif
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(AboutColors.background)
#if APPSTORE
        .sheet(isPresented: $navigationModel.isPaywallSheetPresented) {
            PaywallSheetView(
                proStatusManager: proStatusManager,
                context: .settings
            )
        }
#endif
    }

    private var appIdentity: some View {
        VStack(spacing: DS.Spacing.sm) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 76, height: 76)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: .black.opacity(0.10), radius: 8, y: 4)

            Text(appName)
                .font(DS.Typography.headlineMedium)

            Text(versionText)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var statusRow: some View {
#if APPSTORE
        Button {
            navigationModel.isPaywallSheetPresented = true
        } label: {
            HStack(spacing: DS.Spacing.sm) {
                AboutRowTitle(title: "Status", systemImage: statusIcon)
                Spacer(minLength: 0)
                Text(statusSummary)
                    .foregroundStyle(statusColor)
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
#else
        HStack(spacing: DS.Spacing.sm) {
            Label("Status", systemImage: "heart.circle")
            Spacer(minLength: 0)
            Text("Direct version")
                .foregroundStyle(.secondary)
        }
#endif
    }

    private func copyContactEmail() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(ExternalLinks.contactEmailAddress, forType: .string)
    }

    private var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? "Command Reopen"
    }

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        return "Version \(version) (\(build))"
    }

#if APPSTORE
    private var displayState: ProDisplayState {
        switch previewMode {
        case .live:
            return .live(
                status: proStatusManager.status,
                entitlementSnapshot: proStatusManager.currentEntitlementSnapshot
            )
        case .notPro, .yearlyPro, .lifetimePro:
            return .preview(previewMode)
        }
    }

    private var showsManageSubscriptions: Bool {
        if case .pro(let plan, _, _) = displayState.status {
            return plan == .yearly
        }

        return false
    }

    private var statusIcon: String {
        switch displayState.status {
        case .trial: return "clock.badge.checkmark"
        case .expired: return "exclamationmark.triangle"
        case .pro: return "checkmark.seal"
        }
    }

    private var statusColor: Color {
        switch displayState.status {
        case .trial: return .secondary
        case .expired: return .orange
        case .pro: return DS.Colors.brandPrimary
        }
    }

    private var statusSummary: String {
        switch displayState.status {
        case .trial(let daysRemaining, let expiresAt):
            return "\(daysRemaining) day\(daysRemaining == 1 ? "" : "s") left, expires \(formattedDate(expiresAt))"
        case .expired:
            return "Trial expired - click to upgrade"
        case .pro(let plan, let expirationDate, let willRenew):
            switch plan {
            case .lifetime:
                return "👑 Lifetime Pro"
            case .yearly:
                guard let expirationDate else { return "⭐ Yearly Pro" }
                return "⭐ \(willRenew ? "Renews" : "Ends") \(formattedDate(expirationDate))"
            }
        }
    }

    private func formattedDate(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day().year())
    }
#endif
}

private struct AboutLinkRow: View {
    let title: String
    let value: String
    var urlString: String? = nil
    let systemImage: String
    var trailingSystemImage: String = "arrow.up.right"
    var action: (() -> Void)?

    var body: some View {
        Button {
            if let action {
                action()
                return
            }

            guard let urlString,
                  let url = URL(string: urlString) else { return }
            NSWorkspace.shared.open(url)
        } label: {
            HStack(spacing: DS.Spacing.sm) {
                AboutRowTitle(title: title, systemImage: systemImage)
                Spacer(minLength: DS.Spacing.md)
                Text(value)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Image(systemName: trailingSystemImage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct AboutRowTitle: View {
    let title: String
    let systemImage: String

    var body: some View {
        HStack(spacing: DS.Spacing.sm) {
            Image(systemName: systemImage)
                .font(.body)
                .frame(width: 22, alignment: .leading)
            Text(title)
        }
    }
}

private enum AboutColors {
    static var sectionBackground: Color {
        Color(nsColor: .controlBackgroundColor)
    }

    static var background: Color {
        Color(nsColor: .windowBackgroundColor)
    }
}

// MARK: - Settings Tab Content

struct SettingsTabContent: View {
    @EnvironmentObject private var activationMonitor: ActivationMonitor
    @EnvironmentObject private var accessController: AppAccessController

    private let appLookupProvider = ApplicationLookupProvider()

    @State private var appLookupQuery = ""
    @State private var applicationCatalog: [ExcludedApplicationInfo] = []

    private var isFeatureLocked: Bool {
        !accessController.isCoreFeatureAvailable
    }

    private var appLookupResults: [ExcludedApplicationInfo] {
        appLookupProvider.search(query: appLookupQuery, in: applicationCatalog)
    }

    var body: some View {
        SettingsUI.FormPane {
            Section {
                Toggle("Enable Command Reopen", isOn: activationMonitor.featureToggleBinding)
                    .disabled(isFeatureLocked)
                LaunchAtLogin.Toggle("Launch at Login")
            } footer: {
                if isFeatureLocked {
                    Text("Requires Pro to enable.")
                        .foregroundStyle(Color.accentColor)
                } else {
                    Text("Automatically reopen windows when switching apps via Cmd+Tab")
                        .settingDescription()
                }
            }

            ExcludedAppsSection(
                bundleIDs: activationMonitor.sortedUserExcludedBundleIDs,
                isDisabled: isFeatureLocked,
                removeAction: removeExcludedBundleID
            )
            .opacity(isFeatureLocked ? 0.5 : 1)

            AddExclusionSection(
                query: $appLookupQuery,
                searchResults: appLookupResults,
                excludedBundleIDs: activationMonitor.userExcludedBundleIDs,
                isDisabled: isFeatureLocked,
                addApplicationAction: addLookupResult
            )
            .opacity(isFeatureLocked ? 0.5 : 1)
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

private struct ExcludedAppsSection: View {
    let bundleIDs: [String]
    let isDisabled: Bool
    let removeAction: (String) -> Void

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
        } header: {
            Text("Excluded Apps")
        }
    }
}

private struct AddExclusionSection: View {
    @Binding var query: String
    let searchResults: [ExcludedApplicationInfo]
    let excludedBundleIDs: Set<String>
    let isDisabled: Bool
    let addApplicationAction: (ExcludedApplicationInfo) -> Void

    var body: some View {
        Section {
            LabeledContent("Search") {
                ApplicationSearchControl(
                    query: $query,
                    results: searchResults,
                    excludedBundleIDs: excludedBundleIDs,
                    isDisabled: isDisabled,
                    addAction: addApplicationAction
                )
            }
        } header: {
            Text("Add Exclusion")
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
                        .settingDescription()
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
