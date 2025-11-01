//
//  ComTabApp.swift
//  ComTab
//
//  Created by CHEN on 2025/10/31.
//

import SwiftUI
import AppKit

@main
struct ComTabApp: App {
    @StateObject private var activationMonitor = ActivationMonitor()

    var body: some Scene {
        MenuBarExtra("ComTab", systemImage: "sparkle") {
            MenuContentView()
                .environmentObject(activationMonitor)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
                .environmentObject(activationMonitor)
        }
    }
}

private struct SettingsView: View {
    @EnvironmentObject private var activationMonitor: ActivationMonitor

    private var featureBinding: Binding<Bool> {
        Binding(
            get: { activationMonitor.isFeatureEnabled },
            set: { activationMonitor.isFeatureEnabled = $0 }
        )
    }

    var body: some View {
        Form {
            Toggle("自动重新打开前台应用", isOn: featureBinding)
        }
        .padding(20)
        .frame(width: 320)
    }
}
