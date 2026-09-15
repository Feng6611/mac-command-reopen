//
//  AppDelegate.swift
//  Command Reopen
//
//  Created by CHEN on 2025/10/31.
//

import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let lifecycleCoordinator = AppLifecycleCoordinator.shared

    func applicationWillFinishLaunching(_ notification: Notification) {
        lifecycleCoordinator.applicationWillFinishLaunching()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        lifecycleCoordinator.applicationDidFinishLaunching()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Sent when the user opens an already-running copy — Dock, Spotlight, or
    /// Launchpad. Claimed unconditionally so the app decides what it means.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        lifecycleCoordinator.applicationShouldHandleReopen()
        return true
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        lifecycleCoordinator.applicationDidBecomeActive()
    }

    func applicationWillTerminate(_ notification: Notification) {
        lifecycleCoordinator.applicationWillTerminate()
    }
}
