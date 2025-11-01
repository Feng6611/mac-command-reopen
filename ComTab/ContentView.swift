//
//  ContentView.swift
//  ComTab
//
//  Created by CHEN on 2025/10/31.
//

import SwiftUI
import AppKit

struct MenuContentView: View {
    @EnvironmentObject private var activationMonitor: ActivationMonitor

    private var featureBinding: Binding<Bool> {
        Binding(
            get: { activationMonitor.isFeatureEnabled },
            set: { activationMonitor.isFeatureEnabled = $0 }
        )
    }

    var body: some View {
        Group {
            Toggle(isOn: featureBinding) {
                Text("自动重新打开前台应用")
            }

            Button("立即重新打开前台应用") {
                activationMonitor.relaunchFrontmostApplication()
            }
            .disabled(!activationMonitor.isFeatureEnabled)

            Divider()

            Button("退出 ComTab") {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}

#Preview {
    MenuContentView()
        .environmentObject(ActivationMonitor())
}
