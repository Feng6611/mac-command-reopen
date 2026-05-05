//
//  ComTabApp.swift
//  ComTab
//
//  Created by CHEN on 2025/10/31.
//

import SwiftUI

@main
struct ComTabApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var activationMonitor = ActivationMonitor.shared
    @StateObject private var reopenStatsStore = ReopenStatsStore.shared
    @StateObject private var accessController = AppAccessController.shared
    @StateObject private var settingsNavigationModel = SettingsNavigationModel.shared
#if APPSTORE
    @StateObject private var proStatusManager = ProStatusManager.shared
#endif

    var body: some Scene {
        MenuBarExtra {
            StatusBarMenu()
                .environmentObject(activationMonitor)
                .environmentObject(accessController)
                .background {
                    if #available(macOS 14.0, *) {
                        SettingsOpenActionInstaller()
                    }
                }
        } label: {
            Image(systemName: "command")
                .background {
                    if #available(macOS 14.0, *) {
                        SettingsOpenActionInstaller()
                    }
                }
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
                .environmentObject(activationMonitor)
                .environmentObject(reopenStatsStore)
                .environmentObject(accessController)
                .environmentObject(settingsNavigationModel)
#if APPSTORE
                .environmentObject(proStatusManager)
#endif
        }
    }
}
