//
//  ContentView.swift
//  ComTab
//
//  Created by CHEN on 2025/10/31.
//

import SwiftUI
import AppKit

struct MenuContentView: View {
    @StateObject private var launchAtLogin = LaunchAtLoginManager()

    var body: some View {
        Group {
            Toggle("Launch at Login", isOn: launchAtLogin.binding)
                .disabled(!isAtLeast13)

            Button("About") {
                NSApplication.shared.activate(ignoringOtherApps: true)
                NSApplication.shared.orderFrontStandardAboutPanel(nil)
            }

            Button("Quit Command Reopen") {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}

private var isAtLeast13: Bool {
    if #available(macOS 13.0, *) { return true } else { return false }
}

#Preview {
    MenuContentView()
        .environmentObject(ActivationMonitor())
}
