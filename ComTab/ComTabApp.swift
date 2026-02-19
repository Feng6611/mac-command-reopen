//
//  ComTabApp.swift
//  ComTab
//
//  Created by CHEN on 2025/10/31.
//

import SwiftUI
import AppKit
import StoreKit

@main
struct ComTabApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var activationMonitor = ActivationMonitor()

    var body: some Scene {
        Settings {
            SettingsView()
                .environmentObject(activationMonitor)
        }
    }
}

private struct SettingsView: View {
    @EnvironmentObject private var activationMonitor: ActivationMonitor
    @StateObject private var launchManager = LaunchAtLoginManager()
    @State private var selectedBundleToExclude: String?

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
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
                    Picker("", selection: $selectedBundleToExclude) {
                        Text("Select an app...").tag(String?.none)
                        ForEach(runningUserApps, id: \.bundleIdentifier) { app in
                            if let bundleID = app.bundleIdentifier {
                                Text(app.localizedName ?? bundleID)
                                    .tag(Optional(bundleID))
                            }
                        }
                    }

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

            Section {
                Button {
                    requestReview()
                } label: {
                    Label("Rate on App Store", systemImage: "star.fill")
                }
                .buttonStyle(.link)

                Button {
                    if let url = URL(string: "mailto:fchen6611@gmail.com") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Label("Contact Developer", systemImage: "envelope")
                }
                .buttonStyle(.link)

                Button {
                    if let url = URL(string: "https://github.com/Feng6611/mac-command-reopen") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Label("GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                }
                .buttonStyle(.link)
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
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 380, height: 480)
    }

    private func requestReview() {
        if #available(macOS 14.0, *) {
            // Use the environment-based review request on macOS 14+
            // For simplicity, fall back to opening App Store URL
            openAppStoreReview()
        } else {
            openAppStoreReview()
        }
    }

    private func openAppStoreReview() {
        // TODO: Replace APP_ID with the real App Store ID after first App Store submission.
        let appStoreURL = "macappstore://apps.apple.com/app/idAPP_ID?action=write-review"
        if let url = URL(string: appStoreURL) {
            NSWorkspace.shared.open(url)
        }
    }
}
