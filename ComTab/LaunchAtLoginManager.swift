//
//  LaunchAtLoginManager.swift
//  Command Reopen
//
//  Created by CHEN on 2025/10/31.
//

import Foundation
import SwiftUI
import Combine
import ServiceManagement
import os

final class LaunchAtLoginManager: ObservableObject {
    @Published private(set) var isEnabled: Bool

    init() {
        if #available(macOS 13.0, *) {
            isEnabled = SMAppService.mainApp.status == .enabled
        } else {
            isEnabled = false
        }
    }

    func setEnabled(_ enabled: Bool) {
        guard #available(macOS 13.0, *) else { return }
        do {
            if enabled {
                try SMAppService.mainApp.register()
                AppLogger.launchAtLogin.info("Successfully registered launch at login")
            } else {
                try SMAppService.mainApp.unregister()
                AppLogger.launchAtLogin.info("Successfully unregistered launch at login")
            }
            self.isEnabled = enabled
        } catch {
            // Roll back to actual status on failure
            self.isEnabled = SMAppService.mainApp.status == .enabled
            AppLogger.launchAtLogin.error("Failed to \(enabled ? "register" : "unregister") launch at login: \(error.localizedDescription)")
        }
    }
}

extension LaunchAtLoginManager {
    var binding: Binding<Bool> {
        Binding(
            get: { self.isEnabled },
            set: { self.setEnabled($0) }
        )
    }
}
