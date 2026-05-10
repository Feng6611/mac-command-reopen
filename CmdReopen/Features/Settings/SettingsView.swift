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
    @State private var selectedBundleToExclude: String?
    @State private var appLookupQuery = ""
    @State private var appLookupResult: ExcludedApplicationInfo?
    @State private var appLookupError: String?
    @State private var runningUserApps: [NSRunningApplication] = []

    private var isFeatureLocked: Bool {
        !accessController.isCoreFeatureAvailable
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

            Section {
                if activationMonitor.sortedUserExcludedBundleIDs.isEmpty {
                    Text("No excluded apps")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(activationMonitor.sortedUserExcludedBundleIDs, id: \.self) { bundleID in
                        ExcludedApplicationRow(
                            bundleID: bundleID,
                            removeAction: removeExcludedBundleID
                        )
                    }
                }

                SettingsUI.ApplicationPicker(
                    applications: runningUserApps,
                    selection: $selectedBundleToExclude,
                    isDisabled: isFeatureLocked,
                    addAction: addExcludedBundleID
                )

                AppLookupAddRow(
                    query: $appLookupQuery,
                    result: appLookupResult,
                    errorMessage: appLookupError,
                    isDisabled: isFeatureLocked,
                    isAlreadyExcluded: appLookupResult.map { activationMonitor.userExcludedBundleIDs.contains($0.bundleID) } ?? false,
                    lookupAction: lookupApp,
                    addAction: addLookupResult
                )
            } header: {
                Text("Excluded Apps")
            } footer: {
                Text("Search by app name or bundle ID, for example Safari or com.apple.universalcontrol.")
                    .settingDescription()
            }
            .opacity(isFeatureLocked ? 0.5 : 1)
        }
        .task {
            await Task.yield()
            refreshRunningUserApps()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didLaunchApplicationNotification)) { _ in
            refreshRunningUserApps()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didTerminateApplicationNotification)) { _ in
            refreshRunningUserApps()
        }
        .onChange(of: appLookupQuery) { _ in
            appLookupResult = nil
            appLookupError = nil
        }
    }

    private func addExcludedBundleID(_ bundleID: String) {
        activationMonitor.addExcludedBundleID(bundleID)
        refreshRunningUserApps()
    }

    private func lookupApp() {
        appLookupError = nil
        appLookupResult = nil

        guard let normalizedQuery = ActivationMonitor.normalizeBundleID(appLookupQuery) else {
            appLookupError = "Enter an app name or bundle ID."
            return
        }

        guard let result = ExcludedApplicationInfo.resolve(query: normalizedQuery, runningApplications: runningUserApps) else {
            appLookupError = "No app found for \(normalizedQuery)."
            return
        }

        appLookupResult = result
    }

    private func addLookupResult() {
        if appLookupResult == nil {
            lookupApp()
        }

        guard let result = appLookupResult else {
            return
        }

        guard !activationMonitor.userExcludedBundleIDs.contains(result.bundleID) else {
            appLookupError = "Already excluded."
            return
        }

        activationMonitor.addExcludedBundleID(result.bundleID)
        appLookupQuery = ""
        appLookupResult = nil
        refreshRunningUserApps()
    }

    private func removeExcludedBundleID(_ bundleID: String) {
        activationMonitor.removeExcludedBundleID(bundleID)
        refreshRunningUserApps()
    }

    private func refreshRunningUserApps() {
        let excluded = activationMonitor.userExcludedBundleIDs
        let selfBundleID = Bundle.main.bundleIdentifier

        runningUserApps = NSWorkspace.shared.runningApplications
            .filter { app in
                guard app.activationPolicy == .regular,
                      let bundleID = app.bundleIdentifier else {
                    return false
                }
                return !excluded.contains(bundleID) && bundleID != selfBundleID
            }
            .sorted {
                ($0.localizedName ?? $0.bundleIdentifier ?? "")
                    .localizedCaseInsensitiveCompare($1.localizedName ?? $1.bundleIdentifier ?? "") == .orderedAscending
            }
    }

}

private struct ExcludedApplicationRow: View {
    let bundleID: String
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
            .help("Remove \(applicationInfo.displayName)")
            .accessibilityLabel("Remove \(applicationInfo.displayName)")
        }
    }
}

private struct AppLookupAddRow: View {
    @Binding var query: String
    let result: ExcludedApplicationInfo?
    let errorMessage: String?
    let isDisabled: Bool
    let isAlreadyExcluded: Bool
    let lookupAction: () -> Void
    let addAction: () -> Void

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            HStack(spacing: DS.Spacing.sm) {
                TextField("Bundle ID or App Name", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .disabled(isDisabled)
                    .onSubmit(lookupAction)

                Button("Find", action: lookupAction)
                    .disabled(trimmedQuery.isEmpty || isDisabled)
            }

            if let result {
                HStack(spacing: DS.Spacing.sm) {
                    ApplicationInfoLabel(applicationInfo: result)

                    Spacer(minLength: 0)

                    Button(isAlreadyExcluded ? "Added" : "Add", action: addAction)
                        .disabled(isAlreadyExcluded || isDisabled)
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }
}

private struct ExcludedApplicationInfo {
    let bundleID: String
    let applicationURL: URL?

    var displayName: String {
        guard let applicationURL else {
            return bundleID
        }

        let bundle = Bundle(url: applicationURL)
        return bundle?.localizedInfoDictionary?["CFBundleDisplayName"] as? String
            ?? bundle?.localizedInfoDictionary?["CFBundleName"] as? String
            ?? bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? FileManager.default.displayName(atPath: applicationURL.path)
    }

    init(bundleID: String) {
        self.bundleID = bundleID
        self.applicationURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    init(bundleID: String, applicationURL: URL?) {
        self.bundleID = bundleID
        self.applicationURL = applicationURL
    }

    static func resolve(query: String, runningApplications: [NSRunningApplication]) -> ExcludedApplicationInfo? {
        if let info = resolve(bundleID: query) {
            return info
        }

        if let runningApp = runningApplications.first(where: { app in
            guard let localizedName = app.localizedName else { return false }
            return localizedName.localizedCaseInsensitiveCompare(query) == .orderedSame
        }), let bundleID = runningApp.bundleIdentifier {
            return ExcludedApplicationInfo(
                bundleID: bundleID,
                applicationURL: runningApp.bundleURL
                    ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            )
        }

        if let applicationPath = NSWorkspace.shared.fullPath(forApplication: query) {
            let applicationURL = URL(fileURLWithPath: applicationPath)
            if let bundleID = Bundle(url: applicationURL)?.bundleIdentifier {
                return ExcludedApplicationInfo(bundleID: bundleID, applicationURL: applicationURL)
            }
        }

        if looksLikeBundleID(query) {
            return ExcludedApplicationInfo(bundleID: query, applicationURL: nil)
        }

        return nil
    }

    private static func resolve(bundleID: String) -> ExcludedApplicationInfo? {
        guard looksLikeBundleID(bundleID) else {
            return nil
        }

        let applicationURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        return ExcludedApplicationInfo(bundleID: bundleID, applicationURL: applicationURL)
    }

    private static func looksLikeBundleID(_ value: String) -> Bool {
        value.contains(".") && value.rangeOfCharacter(from: .whitespacesAndNewlines) == nil
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
