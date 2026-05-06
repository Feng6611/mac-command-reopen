//
//  CmdReopenApp.swift
//  CmdReopen
//
//  Created by CHEN on 2025/10/31.
//

import SwiftUI

@main
struct CmdReopenApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var activationMonitor = ActivationMonitor.shared
    @StateObject private var reopenStatsStore = ReopenStatsStore.shared
    @StateObject private var accessController = AppAccessController.shared
    @StateObject private var settingsNavigationModel = SettingsNavigationModel.shared

    var body: some Scene {
        Settings {
            SettingsView()
                .environmentObject(activationMonitor)
                .environmentObject(reopenStatsStore)
                .environmentObject(accessController)
                .environmentObject(settingsNavigationModel)
        }
    }
}
