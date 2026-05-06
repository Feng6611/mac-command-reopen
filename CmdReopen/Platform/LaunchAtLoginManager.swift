//
//  LaunchAtLoginManager.swift
//  Command Reopen
//
//  Created by CHEN on 2025/10/31.
//

import Foundation
import SwiftUI
import Combine
import LaunchAtLogin
import os

final class LaunchAtLoginManager: ObservableObject, LaunchAtLoginManaging {
    @Published private(set) var isEnabled: Bool

    init() {
        isEnabled = LaunchAtLogin.isEnabled
    }

    func setEnabled(_ enabled: Bool) {
        LaunchAtLogin.isEnabled = enabled
        isEnabled = LaunchAtLogin.isEnabled
        AppLogger.launchAtLogin.info("Set launch at login to \(self.isEnabled)")
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
