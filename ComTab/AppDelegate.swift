//
//  AppDelegate.swift
//  Command Reopen
//
//  Created by CHEN on 2025/10/31.
//

import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusController = StatusBarController(activationMonitor: .shared)
        // Ensure no windows are visible
        NSApp.windows.forEach { $0.orderOut(nil) }
    }
}
