//
//  AppDelegate.swift
//  Command Reopen
//
//  Created by CHEN on 2025/10/31.
//

import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let lifecycleCoordinator = AppLifecycleCoordinator.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        lifecycleCoordinator.applicationDidFinishLaunching()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        lifecycleCoordinator.applicationDidBecomeActive()
    }

    func applicationWillTerminate(_ notification: Notification) {
        lifecycleCoordinator.applicationWillTerminate()
    }
}
