//
//  AppLogger.swift
//  ComTab
//
//  Created by CHEN on 2025/10/31.
//

import os
import Foundation

enum AppLogger {
    static let activation = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.dev.kkuk.CmdReopen",
        category: "Activation"
    )
}
