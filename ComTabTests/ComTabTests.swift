//
//  ComTabTests.swift
//  ComTabTests
//
//  Created by CHEN on 2025/10/31.
//

import Foundation
import Testing
@testable import Command_Reopen

struct ComTabTests {

    @Test("Ignored bundle IDs include expected system apps")
    func ignoredBundleIDs() {
        let expected: Set<String> = [
            "com.apple.dock",
            "com.apple.finder",
            "com.apple.Spotlight",
            "com.apple.notificationcenterui",
            "com.apple.controlcenter",
            "com.apple.loginwindow",
            "com.apple.SecurityAgent",
            "com.apple.screencaptureui"
        ]

        for bundleID in expected {
            #expect(ActivationMonitor.ignoredBundleIDs.contains(bundleID))
            #expect(ActivationMonitor.isIgnoredBundleID(bundleID))
        }

        #expect(!ActivationMonitor.isIgnoredBundleID("com.apple.TextEdit"))
        #expect(!ActivationMonitor.isIgnoredBundleID("com.google.Chrome"))
    }

    @Test("Recent launch suppression helper respects interval bounds")
    func recentLaunchSuppressionLogic() {
        let now = Date()

        #expect(ActivationMonitor.shouldSuppressRecentLaunch(
            launchDate: now.addingTimeInterval(-0.3),
            now: now,
            interval: 0.9
        ))

        #expect(!ActivationMonitor.shouldSuppressRecentLaunch(
            launchDate: now.addingTimeInterval(-2.0),
            now: now,
            interval: 0.9
        ))

        #expect(!ActivationMonitor.shouldSuppressRecentLaunch(
            launchDate: now.addingTimeInterval(0.1),
            now: now,
            interval: 0.9
        ))

        #expect(!ActivationMonitor.shouldSuppressRecentLaunch(
            launchDate: nil,
            now: now,
            interval: 0.9
        ))
    }

    @Test("Bundle debounce helper suppresses rapid reopen calls")
    func debounceLogic() {
        let now = Date()

        #expect(ActivationMonitor.shouldDebounceReopen(
            lastReopenDate: now.addingTimeInterval(-0.05),
            now: now,
            interval: 0.1
        ))

        #expect(!ActivationMonitor.shouldDebounceReopen(
            lastReopenDate: now.addingTimeInterval(-0.2),
            now: now,
            interval: 0.1
        ))

        #expect(!ActivationMonitor.shouldDebounceReopen(
            lastReopenDate: nil,
            now: now,
            interval: 0.1
        ))
    }

    @Test("Self-trigger suppression helper handles active/expired windows")
    func selfTriggerSuppressionLogic() {
        let now = Date()

        #expect(ActivationMonitor.shouldIgnoreSelfTriggered(
            until: now.addingTimeInterval(0.2),
            now: now
        ))

        #expect(!ActivationMonitor.shouldIgnoreSelfTriggered(
            until: now.addingTimeInterval(-0.2),
            now: now
        ))

        #expect(!ActivationMonitor.shouldIgnoreSelfTriggered(
            until: nil,
            now: now
        ))
    }
}
