//
//  LaunchPresentationPolicy.swift
//  CmdReopen
//

import Foundation

/// Decides whether a launch or re-launch should put Settings on screen.
///
/// The menu bar icon is a shortcut into Settings, not the only entrance. When
/// the user hides it, a fresh launch takes over that job: it is a gesture they
/// already know, so nothing has to be remembered or looked up. A launch the
/// login item started never does this, or every login would open a window.
enum LaunchPresentationPolicy {
    /// What a launch that is still starting up should show.
    static func shouldOpenSettingsAtLaunch(
        isLoginItemLaunch: Bool,
        showsMenuBarIcon: Bool,
        shouldShowOnboarding: Bool
    ) -> Bool {
        guard !isLoginItemLaunch, !showsMenuBarIcon else {
            return false
        }

        // Onboarding is the foreground presentation for a first launch.
        return !shouldShowOnboarding
    }

    /// What opening an already-running copy should show.
    ///
    /// With the icon visible the menu bar already offers Settings, so the
    /// re-launch keeps doing what it always did: nothing.
    static func shouldOpenSettingsOnReopen(
        showsMenuBarIcon: Bool,
        isOnboardingVisible: Bool
    ) -> Bool {
        !showsMenuBarIcon && !isOnboardingVisible
    }
}
