//
//  SettingsView.swift
//  ComTab
//
//  Created by Codex on 2026/3/28.
//

import AppKit
import StoreKit
import SwiftUI

// MARK: - Sidebar Tab

enum SettingsTab: Int, CaseIterable {
    case general
    case statistics
    case pro

    var title: String {
        switch self {
        case .general: return "General"
        case .statistics: return "Statistics"
        case .pro: return "Pro"
        }
    }

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .statistics: return "chart.bar"
        case .pro: return "star"
        }
    }

    var selectedIcon: String {
        switch self {
        case .general: return "gearshape.fill"
        case .statistics: return "chart.bar.fill"
        case .pro: return "star.fill"
        }
    }
}

// MARK: - Main Settings View

struct SettingsView: View {
    @EnvironmentObject private var activationMonitor: ActivationMonitor
    @EnvironmentObject private var reopenStatsStore: ReopenStatsStore
    @EnvironmentObject private var proStatusManager: ProStatusManager

    @State private var selectedTab: SettingsTab = .general

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    init(initialTab: SettingsTab = .general) {
        _selectedTab = State(initialValue: initialTab)
    }

    var body: some View {
        HStack(spacing: 0) {
            // Sidebar
            VStack(spacing: 2) {
                ForEach(SettingsTab.allCases, id: \.self) { tab in
                    SidebarButton(tab: tab, isSelected: selectedTab == tab) {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedTab = tab
                        }
                    }
                }

                Spacer()

                Text("v\(appVersion) (\(buildNumber))")
                    .font(.system(size: 10))
                    .foregroundColor(Color.secondary.opacity(0.5))
                    .padding(.bottom, 14)
            }
            .padding(.top, 20)
            .padding(.horizontal, 12)
            .frame(width: 150)
            .background(SidebarBackgroundView())

            Divider()

            // Content
            Group {
                switch selectedTab {
                case .general:
                    SettingsTabContent()
                case .statistics:
                    ReopenStatsView()
                case .pro:
                    ProTabContent()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 600, height: 520)
        .task {
            await proStatusManager.refresh()
        }
    }
}

// MARK: - Sidebar Background

private struct SidebarBackgroundView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

// MARK: - Sidebar Button

struct SidebarButton: View {
    let tab: SettingsTab
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        let button = Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: isSelected ? tab.selectedIcon : tab.icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                    .frame(width: 20)
                Text(tab.title)
                    .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(backgroundColor)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundColor(isSelected ? .primary : .primary.opacity(0.85))
        .onHover { hovering in
            isHovering = hovering
        }

        if #available(macOS 14.0, *) {
            button.focusEffectDisabled()
        } else {
            button
        }
    }

    private var backgroundColor: Color {
        if isSelected {
            return Color.accentColor.opacity(0.12)
        } else if isHovering {
            return Color.primary.opacity(0.04)
        }
        return .clear
    }
}

// MARK: - Pro Tab Content

struct ProTabContent: View {
    var body: some View {
        VStack {
            Spacer()
            ProSectionView()
            Spacer()
        }
        .padding(.horizontal, 24)
    }
}

// MARK: - Settings Tab Content

struct GroupedFormStyleModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 13.0, *) {
            content.formStyle(.grouped)
        } else {
            content
        }
    }
}

struct SettingsTabContent: View {
    @EnvironmentObject private var activationMonitor: ActivationMonitor
    @EnvironmentObject private var proStatusManager: ProStatusManager
    @StateObject private var launchManager = LaunchAtLoginManager()
    @State private var selectedBundleToExclude: String?

    private var isFeatureLocked: Bool {
        !proStatusManager.status.isActive
    }

    private var distributionChannel: DistributionChannel {
        DistributionChannel.current
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
                            Text("Requires Pro")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.orange)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule()
                                        .fill(Color.orange.opacity(0.1))
                                )
                        }
                    }
                    Text("Automatically reopen windows when switching apps via Cmd+Tab")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                if #available(macOS 13.0, *) {
                    Toggle("Launch at Login", isOn: launchManager.binding)
                }
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
