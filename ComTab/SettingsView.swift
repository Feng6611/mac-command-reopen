//
//  SettingsView.swift
//  ComTab
//
//  Created by Codex on 2026/3/28.
//

import AppKit
import StoreKit
import SwiftUI

struct GroupedFormStyleModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 13.0, *) {
            content.formStyle(.grouped)
        } else {
            content
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var activationMonitor: ActivationMonitor
    @EnvironmentObject private var reopenStatsStore: ReopenStatsStore
    @StateObject private var launchManager = LaunchAtLoginManager()
    @State private var selectedBundleToExclude: String?

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
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
                Toggle("Auto-reopen windows", isOn: activationMonitor.featureToggleBinding)
                if #available(macOS 13.0, *) {
                    Toggle("Launch at Login", isOn: launchManager.binding)
                }
            } header: {
                Text("General")
            }

            Section {
                if activationMonitor.sortedUserExcludedBundleIDs.isEmpty {
                    Text("No excluded apps")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(activationMonitor.sortedUserExcludedBundleIDs, id: \.self) { bundleID in
                        HStack {
                            Text(bundleID)
                                .font(.caption)
                                .textSelection(.enabled)
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

                    Button("Add") {
                        if let selectedBundleToExclude {
                            activationMonitor.addExcludedBundleID(selectedBundleToExclude)
                            self.selectedBundleToExclude = nil
                        }
                    }
                    .disabled(selectedBundleToExclude == nil)
                }
            } header: {
                Text("Excluded Apps")
            }

            ReopenStatsView()

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
                        Label("Official", systemImage: "globe")
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

            Section {
                HStack {
                    Spacer()
                    Text("Command Reopen v\(appVersion) (\(buildNumber))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
        }
        .modifier(GroupedFormStyleModifier())
        .padding(20)
        .frame(width: 420, height: 560)
    }

    private func requestReview() {
        if #available(macOS 14.0, *) {
            openAppStoreReview()
        } else {
            openAppStoreReview()
        }
    }

    private func openAppStoreReview() {
        openURL(AppStoreLinks.reviewURL)
    }

    private func openURL(_ urlString: String) {
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
}
