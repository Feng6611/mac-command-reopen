//
//  SettingsView.swift
//  ComTab
//
//  Created by Codex on 2026/3/28.
//

import AppKit
import LaunchAtLogin
import SwiftUI

// MARK: - Settings Tab

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
        case .statistics: return "chart.bar.xaxis"
        case .pro:
            switch distributionChannel {
            case .appStore: return "star.circle"
            case .direct: return "heart.circle"
            }
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

            ReopenStatsView()
                .tabItem { tabLabel(for: .statistics) }
                .tag(SettingsTab.statistics)

            if accessController.showsProTab {
                Group {
#if APPSTORE
                    ProTabContent()
#else
                    DirectSupportTabContent()
#endif
                }
                .tabItem { tabLabel(for: .pro) }
                .tag(SettingsTab.pro)
            }
        }
        .frame(width: DS.Settings.windowWidth, height: DS.Settings.windowHeight)
        .task {
            await accessController.refresh()
        }
        .onAppear {
            if !accessController.showsProTab && navigationModel.selectedTab == .pro {
                navigationModel.selectedTab = .general
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

    private func tabLabel(for tab: SettingsTab) -> Label<Text, Image> {
        Label(
            tab.title(for: accessController.distributionChannel),
            systemImage: tab.icon(for: accessController.distributionChannel)
        )
    }
}

private extension View {
    func settingsTabPane() -> some View {
        self
            .scenePadding()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

// MARK: - Pro Tab Content

#if APPSTORE
struct ProTabContent: View {
    var body: some View {
        ScrollView(showsIndicators: false) {
            ProSectionView()
                .padding(.vertical, DS.Spacing.lg)
        }
        .padding(.horizontal, DS.Spacing.lg)
    }
}
#else
struct DirectSupportTabContent: View {
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: DS.Spacing.lg) {
                supportCard
                    .padding(.top, DS.Spacing.lg)
            }
        }
        .padding(.horizontal, DS.Spacing.lg)
    }

    private var supportCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: DS.Spacing.md) {
                DSIconBadge(
                    systemName: "heart.fill",
                    iconColor: .accentColor,
                    backgroundColor: DS.Colors.accentTint,
                    size: 36,
                    iconSize: 16
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
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.top, DS.Spacing.lg)
            .padding(.bottom, DS.Spacing.md)
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
            .padding(.horizontal, DS.Spacing.lg)
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
            .padding(.horizontal, DS.Spacing.lg)
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
                        Toggle("Enable Command Reopen", isOn: activationMonitor.featureToggleBinding)
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
                LaunchAtLogin.Toggle("Launch at Login")
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
