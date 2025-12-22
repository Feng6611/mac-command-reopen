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
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var activationMonitor = ActivationMonitor()

    var body: some Scene {
        // 无主窗口，仅提供设置面板以供需要时调整开关
        Settings {
            SettingsView()
                .environmentObject(activationMonitor)
        }
    }
}

private struct SettingsView: View {
    @EnvironmentObject private var activationMonitor: ActivationMonitor

    var body: some View {
        Form {
            Toggle("自动重新打开前台应用", isOn: activationMonitor.featureToggleBinding)
        }
        .padding(20)
        .frame(width: 320)
    }
}
