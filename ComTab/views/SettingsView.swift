//
//  SettingsView.swift
//  ComTab
//
//  Created by Codex on 2026/3/28.
//

import AppKit
import SwiftUI

// MARK: - Sidebar Tab

enum SettingsTab: Int, CaseIterable {
    case general
    case statistics
    case pro

    static func visibleTabs(showProTab: Bool) -> [SettingsTab] {
        showProTab ? [.general, .statistics, .pro] : [.general, .statistics]
    }

    func title(for distributionChannel: DistributionChannel) -> String {
        switch self {
        case .general: return "General"
        case .statistics: return "Statistics"
        case .pro:
            switch distributionChannel {
            case .appStore: return "Pro"
            case .direct: return "Support"
            }
        }
    }

    func icon(for distributionChannel: DistributionChannel) -> String {
        switch self {
        case .general: return "gearshape"
        case .statistics: return "chart.bar"
        case .pro:
            switch distributionChannel {
            case .appStore: return "star"
            case .direct: return "heart"
            }
        }
    }

    func selectedIcon(for distributionChannel: DistributionChannel) -> String {
        switch self {
        case .general: return "gearshape.fill"
        case .statistics: return "chart.bar.fill"
        case .pro:
            switch distributionChannel {
            case .appStore: return "star.fill"
            case .direct: return "heart.fill"
            }
        }
    }
}

// MARK: - Main Settings View

struct SettingsView: View {
    @EnvironmentObject private var activationMonitor: ActivationMonitor
    @EnvironmentObject private var reopenStatsStore: ReopenStatsStore
    @EnvironmentObject private var accessController: AppAccessController
    @EnvironmentObject private var navigationModel: SettingsNavigationModel
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
                .navigationSplitViewColumnWidth(
                    min: DS.Settings.sidebarWidth,
                    ideal: DS.Settings.sidebarWidth,
                    max: DS.Settings.sidebarWidth
                )
        } detail: {
            detail
        }
        .navigationSplitViewStyle(.balanced)
        .frame(width: DS.Settings.windowWidth, height: DS.Settings.windowHeight)
        .task {
            await accessController.refresh()
        }
        .onAppear {
            columnVisibility = .all
            if !accessController.showsProTab && navigationModel.selectedTab == .pro {
                navigationModel.selectedTab = .general
            }
        }
        .onChange(of: columnVisibility) { visibility in
            if visibility != .all {
                columnVisibility = .all
            }
        }
        .onChange(of: accessController.showsProTab) { showsProTab in
            if !showsProTab && navigationModel.selectedTab == .pro {
                navigationModel.selectedTab = .general
            }
        }
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

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: selectedTabBinding) {
                ForEach(SettingsTab.visibleTabs(showProTab: accessController.showsProTab), id: \.self) { tab in
                    SettingsSidebarLabel(
                        tab: tab,
                        isSelected: navigationModel.selectedTab == tab,
                        distributionChannel: accessController.distributionChannel
                    )
                    .tag(tab)
                    .frame(height: DS.Settings.sidebarRowHeight)
                }
            }
            .listStyle(.sidebar)
            .environment(\.defaultMinListRowHeight, DS.Settings.sidebarRowHeight)

            Spacer(minLength: 0)

            Text("v\(appVersion) (\(buildNumber))")
                .font(DS.Typography.body)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, DS.Settings.sidebarHorizontalPadding)
        }
        .padding(.bottom, DS.Settings.sidebarBottomPadding)
        .frame(maxHeight: .infinity)
    }

    private var detail: some View {
        VStack(spacing: DS.Spacing.lg) {
            Text(navigationModel.selectedTab.title(for: accessController.distributionChannel))
                .font(DS.Typography.title3Emphasized)
                .frame(maxWidth: .infinity, alignment: .leading)

            Group {
                switch navigationModel.selectedTab {
                case .general:
                    SettingsTabContent()
                case .statistics:
                    ReopenStatsView()
                case .pro:
#if APPSTORE
                    ProTabContent()
#else
                    DirectSupportTabContent()
#endif
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .padding(.horizontal, DS.Settings.detailHorizontalPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

private struct SettingsSidebarLabel: View {
    let tab: SettingsTab
    let isSelected: Bool
    let distributionChannel: DistributionChannel

    var body: some View {
        Label {
            Text(tab.title(for: distributionChannel))
                .font(DS.Typography.bodyEmphasized)
        } icon: {
            Image(systemName: isSelected ? tab.selectedIcon(for: distributionChannel) : tab.icon(for: distributionChannel))
                .font(DS.Typography.bodyEmphasized)
                .frame(width: 18)
        }
    }
}

// MARK: - Pro Tab Content

#if APPSTORE
struct ProTabContent: View {
    var body: some View {
        ScrollView(showsIndicators: false) {
            ProSectionView()
                .padding(.vertical, DS.Spacing.xxl)
        }
        .padding(.horizontal, DS.Spacing.xxl)
    }
}
#else
struct DirectSupportTabContent: View {
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: DS.Spacing.xl) {
                supportCard
                    .padding(.top, DS.Spacing.xxl)
            }
        }
        .padding(.horizontal, DS.Spacing.xxl)
    }

    private var supportCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: DS.Spacing.md) {
                DSIconBadge(
                    systemName: "heart.fill",
                    iconColor: .accentColor,
                    backgroundColor: DS.Colors.accentTint,
                    size: 42,
                    iconSize: 18
                )

                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    Text("Support Command Reopen")
                        .font(DS.Typography.headlineMedium)
                    Text("The Mac App Store version is the mainline release for ongoing updates and long-term support.")
                        .font(DS.Typography.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, DS.Spacing.xl)
            .padding(.top, DS.Spacing.xl)
            .padding(.bottom, DS.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.Colors.accentTintSubtle)

            Divider()

            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                DirectSupportPoint(
                    title: "Mainline updates",
                    description: "Bug fixes, polish, and future improvements will continue shipping through the App Store version."
                )
                DirectSupportPoint(
                    title: "Support the developer directly",
                    description: "If Command Reopen is useful in your workflow, using the App Store version is the clearest way to support continued work."
                )
                DirectSupportPoint(
                    title: "Same focused product direction",
                    description: "The goal stays the same: keep the app lightweight, reliable, and continuously maintained."
                )
            }
            .padding(.horizontal, DS.Spacing.xl)
            .padding(.top, DS.Spacing.md)
            .padding(.bottom, DS.Spacing.sm)

            HStack(spacing: DS.Spacing.md) {
                Button {
                    openURL(AppStoreLinks.productURL)
                } label: {
                    Label("Open Mac App Store", systemImage: "bag")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    openURL(ExternalLinks.githubURL)
                } label: {
                    Label("View GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, DS.Spacing.xl)
            .padding(.vertical, DS.Spacing.sm)
        }
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
        .dsCard()
    }

    private func openURL(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }
}

private struct DirectSupportPoint: View {
    let title: String
    let description: String

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            Text(title)
                .font(DS.Typography.bodyMedium)
            Text(description)
                .font(DS.Typography.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
#endif

// MARK: - Settings Tab Content

struct GroupedFormStyleModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.formStyle(.grouped)
    }
}

struct SettingsTabContent: View {
    @EnvironmentObject private var activationMonitor: ActivationMonitor
    @EnvironmentObject private var accessController: AppAccessController
    @StateObject private var launchManager = LaunchAtLoginManager()
    @State private var selectedBundleToExclude: String?

    private var isFeatureLocked: Bool {
        !accessController.isCoreFeatureAvailable
    }

    private var distributionChannel: DistributionChannel {
        accessController.distributionChannel
    }

    private var runningUserApps: [NSRunningApplication] {
        let excluded = activationMonitor.userExcludedBundleIDs
        let selfBundleID = Bundle.main.bundleIdentifier

        return NSWorkspace.shared.runningApplications
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

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Toggle("Auto-reopen windows", isOn: activationMonitor.featureToggleBinding)
                            .disabled(isFeatureLocked)
                        if isFeatureLocked {
                            Spacer()
                            HStack(spacing: 3) {
                                Image(systemName: "lock.fill")
                                    .font(.system(size: 8, weight: .semibold))
                                Text("Pro")
                                    .font(.system(size: 10, weight: .semibold))
                            }
                            .foregroundColor(.accentColor)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(
                                Capsule().fill(DS.Colors.accentTint)
                            )
                        }
                    }
                    Text("Automatically reopen windows when switching apps via Cmd+Tab")
                        .font(DS.Typography.caption)
                        .foregroundColor(.secondary)
                }
                Toggle("Launch at Login", isOn: launchManager.binding)
            }

            Section {
                if activationMonitor.sortedUserExcludedBundleIDs.isEmpty {
                    Text("No excluded apps")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(activationMonitor.sortedUserExcludedBundleIDs, id: \.self) { bundleID in
                        HStack(spacing: 8) {
                            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                                    .resizable()
                                    .frame(width: 16, height: 16)
                                Text(FileManager.default.displayName(atPath: url.path))
                                    .font(.caption)
                                    .help(bundleID)
                            } else {
                                Text(bundleID)
                                    .font(.caption)
                            }
                            Spacer()
                            Button {
                                activationMonitor.removeExcludedBundleID(bundleID)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }

                HStack {
                    Picker(selection: $selectedBundleToExclude) {
                        Text("Select an app...").tag(String?.none)
                        ForEach(runningUserApps, id: \.bundleIdentifier) { app in
                            if let bundleID = app.bundleIdentifier {
                                Text(app.localizedName ?? bundleID)
                                    .tag(Optional(bundleID))
                            }
                        }
                    } label: {
                        EmptyView()
                    }
                    .labelsHidden()
                    .disabled(isFeatureLocked)

                    Button("Add") {
                        if let selectedBundleToExclude {
                            activationMonitor.addExcludedBundleID(selectedBundleToExclude)
                            self.selectedBundleToExclude = nil
                        }
                    }
                    .disabled(selectedBundleToExclude == nil || isFeatureLocked)
                }
            } header: {
                Text("Excluded Apps")
            }
            .opacity(isFeatureLocked ? 0.5 : 1)

            Section {
                Button {
                    openURL(ExternalLinks.contactEmail)
                } label: {
                    Label("Contact Developer", systemImage: "envelope")
                }
                .buttonStyle(.link)

                switch distributionChannel {
                case .appStore:
                    Button {
                        openURL(ExternalLinks.officialURL)
                    } label: {
                        Label("Official Website", systemImage: "globe")
                    }
                    .buttonStyle(.link)

                    Button {
                        requestReview()
                    } label: {
                        Label("Rate on App Store", systemImage: "star.fill")
                    }
                    .buttonStyle(.link)

                case .direct:
                    Button {
                        openURL(AppStoreLinks.productURL)
                    } label: {
                        Label("Get on Mac App Store", systemImage: "bag")
                    }
                    .buttonStyle(.link)

                    Button {
                        openURL(ExternalLinks.githubURL)
                    } label: {
                        Label("GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                    .buttonStyle(.link)
                }
            } header: {
                Text("Feedback & Support")
            }
        }
        .modifier(GroupedFormStyleModifier())
    }

    private func requestReview() {
        openURL(AppStoreLinks.reviewURL)
    }

    private func openURL(_ urlString: String) {
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
}
