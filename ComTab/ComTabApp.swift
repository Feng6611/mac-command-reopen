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

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
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
        .frame(width: 380, height: 320)
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
        // Replace APP_ID with actual App Store ID after publishing
        let appStoreURL = "macappstore://apps.apple.com/app/idAPP_ID?action=write-review"
        if let url = URL(string: appStoreURL) {
            NSWorkspace.shared.open(url)
        }
    }
}
