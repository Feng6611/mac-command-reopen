//
//  ComTabTests.swift
//  ComTabTests
//
//  Created by CHEN on 2025/10/31.
//

import AppKit
import Foundation
import Testing
import CoreGraphics
@testable import Command_Reopen

struct ComTabTests {
    @MainActor
    private func makeStatsStore(suiteName: String = UUID().uuidString) -> (ReopenStatsStore, UserDefaults, String) {
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (ReopenStatsStore(defaults: defaults, storageKey: "test.reopenStats"), defaults, suiteName)
    }

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

    @Test("Bundle ID normalization for user exclude list")
    func normalizeBundleID() {
        #expect(ActivationMonitor.normalizeBundleID(" com.apple.TextEdit ") == "com.apple.TextEdit")
        #expect(ActivationMonitor.normalizeBundleID("\n\t") == nil)
        #expect(ActivationMonitor.normalizeBundleID("") == nil)
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

    @Test("Rapid-return heuristic suppresses short tab-away-and-back cycles")
    func rapidReturnSuppressionLogic() {
        let now = Date()

        #expect(ActivationMonitor.shouldSuppressRapidReturn(
            previousFrontmostBundleID: "com.apple.Safari",
            targetBundleID: "com.apple.TextEdit",
            targetLastActivationDate: now.addingTimeInterval(-1.0),
            previousBundleLastActivationDate: now.addingTimeInterval(-0.4),
            now: now,
            interval: 2.0
        ))

        #expect(!ActivationMonitor.shouldSuppressRapidReturn(
            previousFrontmostBundleID: "com.apple.TextEdit",
            targetBundleID: "com.apple.TextEdit",
            targetLastActivationDate: now.addingTimeInterval(-1.0),
            previousBundleLastActivationDate: now.addingTimeInterval(-0.4),
            now: now,
            interval: 2.0
        ))

        #expect(!ActivationMonitor.shouldSuppressRapidReturn(
            previousFrontmostBundleID: "com.apple.Safari",
            targetBundleID: "com.apple.TextEdit",
            targetLastActivationDate: now.addingTimeInterval(-3.0),
            previousBundleLastActivationDate: now.addingTimeInterval(-0.4),
            now: now,
            interval: 2.0
        ))

        #expect(!ActivationMonitor.shouldSuppressRapidReturn(
            previousFrontmostBundleID: nil,
            targetBundleID: "com.apple.TextEdit",
            targetLastActivationDate: now.addingTimeInterval(-1.0),
            previousBundleLastActivationDate: now.addingTimeInterval(-0.4),
            now: now,
            interval: 2.0
        ))
    }

    @Test("Visible window detection only matches onscreen windows for the target app")
    func visibleWindowDetection() {
        let targetPID: pid_t = 4242
        let otherPID: pid_t = 8080

        let visibleWindow: [String: Any] = [
            kCGWindowOwnerPID as String: NSNumber(value: targetPID),
            kCGWindowIsOnscreen as String: true,
            kCGWindowAlpha as String: 1.0,
            kCGWindowBounds as String: [
                "X": 40,
                "Y": 80,
                "Width": 1024,
                "Height": 768
            ]
        ]

        let hiddenWindow: [String: Any] = [
            kCGWindowOwnerPID as String: NSNumber(value: targetPID),
            kCGWindowIsOnscreen as String: false,
            kCGWindowAlpha as String: 1.0,
            kCGWindowBounds as String: [
                "X": 0,
                "Y": 0,
                "Width": 1024,
                "Height": 768
            ]
        ]

        let tinyOverlay: [String: Any] = [
            kCGWindowOwnerPID as String: NSNumber(value: targetPID),
            kCGWindowIsOnscreen as String: true,
            kCGWindowAlpha as String: 1.0,
            kCGWindowBounds as String: [
                "X": 0,
                "Y": 0,
                "Width": 12,
                "Height": 12
            ]
        ]

        let otherAppWindow: [String: Any] = [
            kCGWindowOwnerPID as String: NSNumber(value: otherPID),
            kCGWindowIsOnscreen as String: true,
            kCGWindowAlpha as String: 1.0,
            kCGWindowBounds as String: [
                "X": 0,
                "Y": 0,
                "Width": 1280,
                "Height": 720
            ]
        ]

        #expect(ActivationMonitor.hasVisibleWindow(
            ownerPID: targetPID,
            windowInfoList: [visibleWindow, otherAppWindow],
            minimumDimension: 32
        ))

        #expect(!ActivationMonitor.hasVisibleWindow(
            ownerPID: targetPID,
            windowInfoList: [hiddenWindow, tinyOverlay, otherAppWindow],
            minimumDimension: 32
        ))
    }

    @Test("Window owner PID helper accepts common CoreGraphics number types")
    func windowOwnerPIDParsing() {
        #expect(ActivationMonitor.windowOwnerPID(from: [
            kCGWindowOwnerPID as String: NSNumber(value: 123)
        ]) == 123)

        #expect(ActivationMonitor.windowOwnerPID(from: [
            kCGWindowOwnerPID as String: Int32(456)
        ]) == 456)

        #expect(ActivationMonitor.windowOwnerPID(from: [
            kCGWindowOwnerPID as String: 789
        ]) == 789)

        #expect(ActivationMonitor.windowOwnerPID(from: [:]) == nil)
    }

    @MainActor
    @Test("Successful reopen stats increment total and per-app counts")
    func reopenStatsIncrement() {
        let (store, defaults, suiteName) = makeStatsStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        store.recordSuccessfulReopen(bundleID: "com.apple.TextEdit", localizedName: "TextEdit")

        #expect(store.totalSuccessfulReopens == 1)
        #expect(store.appStats.count == 1)
        #expect(store.appStats[0] == .init(bundleID: "com.apple.TextEdit", displayName: "TextEdit", count: 1))
    }

    @MainActor
    @Test("Successful reopen stats accumulate and sort by count")
    func reopenStatsSorting() {
        let (store, defaults, suiteName) = makeStatsStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        store.recordSuccessfulReopen(bundleID: "com.apple.TextEdit", localizedName: "TextEdit")
        store.recordSuccessfulReopen(bundleID: "com.apple.Safari", localizedName: "Safari")
        store.recordSuccessfulReopen(bundleID: "com.apple.TextEdit", localizedName: "TextEdit")

        #expect(store.totalSuccessfulReopens == 3)
        #expect(store.appStats.map(\.bundleID) == ["com.apple.TextEdit", "com.apple.Safari"])
        #expect(store.appStats.map(\.count) == [2, 1])
    }

    @MainActor
    @Test("Successful reopen stats persist across store reloads")
    func reopenStatsPersistence() {
        let suiteName = UUID().uuidString
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let firstStore = ReopenStatsStore(defaults: defaults, storageKey: "test.reopenStats")
        firstStore.recordSuccessfulReopen(bundleID: "com.apple.TextEdit", localizedName: "TextEdit")
        firstStore.recordSuccessfulReopen(bundleID: "com.apple.TextEdit", localizedName: "TextEdit")

        let secondStore = ReopenStatsStore(defaults: defaults, storageKey: "test.reopenStats")
        #expect(secondStore.totalSuccessfulReopens == 2)
        #expect(secondStore.appStats == [.init(bundleID: "com.apple.TextEdit", displayName: "TextEdit", count: 2)])
    }

    @MainActor
    @Test("Reset clears reopen stats")
    func reopenStatsReset() {
        let (store, defaults, suiteName) = makeStatsStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        store.recordSuccessfulReopen(bundleID: "com.apple.TextEdit", localizedName: "TextEdit")
        store.reset()

        #expect(store.totalSuccessfulReopens == 0)
        #expect(store.appStats.isEmpty)
    }

    @MainActor
    @Test("Activation monitor records stats only for successful reopen completions")
    func activationMonitorReopenCompletionStats() {
        let suiteName = UUID().uuidString
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let statsStore = ReopenStatsStore(defaults: defaults, storageKey: "test.reopenStats")
        let monitor = ActivationMonitor(
            notificationCenter: NotificationCenter(),
            workspace: .shared,
            defaults: defaults,
            reopenStatsStore: statsStore
        )

        monitor.handleReopenCompletion(
            requestedBundleID: "com.apple.TextEdit",
            openedBundleID: nil,
            localizedName: nil,
            openedProcessIdentifier: nil,
            error: NSError(domain: "Test", code: 1)
        )
        #expect(statsStore.totalSuccessfulReopens == 0)

        monitor.handleReopenCompletion(
            requestedBundleID: "com.apple.TextEdit",
            openedBundleID: "com.apple.TextEdit",
            localizedName: "TextEdit",
            openedProcessIdentifier: 123,
            error: nil
        )
        #expect(statsStore.totalSuccessfulReopens == 1)
        #expect(statsStore.appStats == [.init(bundleID: "com.apple.TextEdit", displayName: "TextEdit", count: 1)])
    }

}
