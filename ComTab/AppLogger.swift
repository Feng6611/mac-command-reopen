//
//  AppLogger.swift
//  ComTab
//
//  Created by CHEN on 2025/10/31.
//

import os
import Foundation

enum AppLogger {
    static let buildSignature: String = {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
        return "\(version) (\(build))"
    }()

    static let lifecycle = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.dev.kkuk.CmdReopen",
        category: "Lifecycle"
    )

    static let activation = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.dev.kkuk.CmdReopen",
        category: "Activation"
    )

    static let launchAtLogin = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.dev.kkuk.CmdReopen",
        category: "LaunchAtLogin"
    )

    static let purchase = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.dev.kkuk.CmdReopen",
        category: "Purchase"
    )
}
