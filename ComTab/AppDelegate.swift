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
        statusController = StatusBarController()
        // 确保没有窗口露出
        NSApp.windows.forEach { $0.orderOut(nil) }
    }
}
