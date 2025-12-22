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
            } else {
                try SMAppService.mainApp.unregister()
            }
            self.isEnabled = enabled
        } catch {
            // Roll back to actual status on failure
            self.isEnabled = SMAppService.mainApp.status == .enabled
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
