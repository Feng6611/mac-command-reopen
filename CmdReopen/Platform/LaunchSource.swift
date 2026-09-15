//
//  LaunchSource.swift
//  CmdReopen
//

import AppKit
import Carbon

/// How macOS started this process, as far as the product needs to distinguish.
protocol LaunchSourceProviding {
    /// True when macOS started this process as the login item rather than the
    /// user opening the app.
    var isLoginItemLaunch: Bool { get }
}

/// Reads the documented login-item attribute from the launch Apple Event.
///
/// `keyAELaunchedAsLogInItem` is present only in the `kAEOpenApplication`
/// event macOS sends when the login item starts the app. That is the one launch
/// that must stay silent — a window there would appear on screen at every
/// login. Every other launch (Finder, Spotlight, Launchpad, `open`, or opening
/// an already-running copy) counts as the user asking for the app.
///
/// The event is only readable while launch is being processed, so callers must
/// ask before the first run loop turn passes.
struct SystemLaunchSource: LaunchSourceProviding {
    var isLoginItemLaunch: Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent else {
            return false
        }

        return event.attributeDescriptor(forKeyword: AEKeyword(keyAELaunchedAsLogInItem)) != nil
    }
}
