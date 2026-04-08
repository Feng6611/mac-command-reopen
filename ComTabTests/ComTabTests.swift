//
//  ComTabTests.swift
//  ComTabTests
//
//  Created by CHEN on 2025/10/31.
//

import AppKit
import Combine
import Foundation
import Testing
import CoreGraphics
import RevenueCat
@testable import Command_Reopen

@MainActor
final class MockCommerceStateSource: CommerceStateSource {
    var entitlementState: AccessEntitlementState
    var isFirstLaunch: Bool
    var shouldOpenProSettings: Bool

    private let entitlementSubject: CurrentValueSubject<AccessEntitlementState, Never>
    private let promptSubject: CurrentValueSubject<Bool, Never>

    init(
        entitlementState: AccessEntitlementState = .unrestricted,
        isFirstLaunch: Bool = false,
        shouldOpenProSettings: Bool = false
    ) {
        self.entitlementState = entitlementState
        self.isFirstLaunch = isFirstLaunch
        self.shouldOpenProSettings = shouldOpenProSettings
        self.entitlementSubject = CurrentValueSubject(entitlementState)
        self.promptSubject = CurrentValueSubject(shouldOpenProSettings)
    }

    var entitlementStatePublisher: AnyPublisher<AccessEntitlementState, Never> {
        entitlementSubject.eraseToAnyPublisher()
    }

    var proSettingsPromptPublisher: AnyPublisher<Bool, Never> {
        promptSubject.eraseToAnyPublisher()
    }

    func configureIfNeeded() {}

    func refresh() async {}

    func markPromptHandled() {
        shouldOpenProSettings = false
        promptSubject.send(false)
    }

    func update(entitlementState: AccessEntitlementState) {
        self.entitlementState = entitlementState
        entitlementSubject.send(entitlementState)
    }

    func updatePrompt(_ shouldOpen: Bool) {
        shouldOpenProSettings = shouldOpen
        promptSubject.send(shouldOpen)
    }
}

@MainActor
final class MockRevenueCatService: RevenueCatServicing {
    var cachedEntitlementSnapshot: ProEntitlementSnapshot?
    var customerInfoDidChange: ((ProEntitlementSnapshot?) -> Void)?

    var currentOffering: Offering?
    var fetchedEntitlementSnapshot: ProEntitlementSnapshot?
    var fetchedEntitlementSnapshots: [ProEntitlementSnapshot?] = []
    var purchaseSnapshot: ProEntitlementSnapshot?
    var restoreSnapshot: ProEntitlementSnapshot?
    var offeringsError: Error?
    var entitlementError: Error?
    var purchaseError: Error?
    var restoreError: Error?
    var configureCallCount = 0
    var fetchCurrentOfferingCallCount = 0
    var fetchEntitlementSnapshotCallCount = 0
    var purchaseDelayNanoseconds: UInt64?
    var restoreDelayNanoseconds: UInt64?

    func configureIfNeeded() {
        configureCallCount += 1
    }

    func fetchCurrentOffering() async throws -> Offering? {
        fetchCurrentOfferingCallCount += 1

        if let offeringsError {
            throw offeringsError
        }

        return currentOffering
    }

    func fetchEntitlementSnapshot() async throws -> ProEntitlementSnapshot? {
        fetchEntitlementSnapshotCallCount += 1

        if let entitlementError {
            throw entitlementError
        }

        if !fetchedEntitlementSnapshots.isEmpty {
            return fetchedEntitlementSnapshots.removeFirst()
        }

        return fetchedEntitlementSnapshot
    }

    func purchase(plan: ProPlan, offering: Offering?) async throws -> ProEntitlementSnapshot? {
        if let purchaseDelayNanoseconds {
            try? await Task.sleep(nanoseconds: purchaseDelayNanoseconds)
        }

        if let purchaseError {
            throw purchaseError
        }

        return purchaseSnapshot
    }

    func restorePurchases() async throws -> ProEntitlementSnapshot? {
        if let restoreDelayNanoseconds {
            try? await Task.sleep(nanoseconds: restoreDelayNanoseconds)
        }

        if let restoreError {
            throw restoreError
        }

        return restoreSnapshot
    }
}

@MainActor
final class MockLegacyAppPurchaseTracker: LegacyAppPurchaseChecking {
    var cachedLegacyAppPurchaseSnapshot: LegacyAppPurchaseSnapshot?
    var refreshedLegacyAppPurchaseSnapshot: LegacyAppPurchaseSnapshot?

    func refreshLegacyAppPurchaseSnapshot() async -> LegacyAppPurchaseSnapshot? {
        let snapshot = refreshedLegacyAppPurchaseSnapshot ?? cachedLegacyAppPurchaseSnapshot

        guard let snapshot else {
            return nil
        }

        return snapshot.originalAppVersion.compare(
            ProStatusManager.Constants.grandfatheringCutoffVersion,
            options: .numeric
        ) == .orderedAscending ? snapshot : nil
    }
}

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
        #expect(!ActivationMonitor.isIgnoredBundleID("com.apple.finder"))
    }

    @Test("Bundle ID normalization for user exclude list")
    func normalizeBundleID() {
        #expect(ActivationMonitor.normalizeBundleID(" com.apple.TextEdit ") == "com.apple.TextEdit")
        #expect(ActivationMonitor.normalizeBundleID("\n\t") == nil)
        #expect(ActivationMonitor.normalizeBundleID("") == nil)
    }

    @MainActor
    @Test("Activation monitor defaults Finder into the user exclude list")
    func activationMonitorDefaultsFinderExclusion() {
        let suiteName = UUID().uuidString
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let monitor = ActivationMonitor(
            notificationCenter: NotificationCenter(),
            workspace: .shared,
            defaults: defaults,
            reopenStatsStore: ReopenStatsStore(defaults: defaults, storageKey: "test.reopenStats"),
            accessController: AppAccessController(distributionChannel: .direct)
        )

        #expect(monitor.userExcludedBundleIDs.contains("com.apple.finder"))
        #expect(defaults.stringArray(forKey: "com.comtab.excludedBundleIDs")?.contains("com.apple.finder") == true)
    }

    @MainActor
    @Test("Activation monitor migrates Finder into existing exclude list once")
    func activationMonitorMigratesFinderIntoExistingExcludeList() {
        let suiteName = UUID().uuidString
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(["com.apple.TextEdit"], forKey: "com.comtab.excludedBundleIDs")

        let monitor = ActivationMonitor(
            notificationCenter: NotificationCenter(),
            workspace: .shared,
            defaults: defaults,
            reopenStatsStore: ReopenStatsStore(defaults: defaults, storageKey: "test.reopenStats"),
            accessController: AppAccessController(distributionChannel: .direct)
        )

        #expect(monitor.userExcludedBundleIDs == ["com.apple.TextEdit", "com.apple.finder"])
    }

    @MainActor
    @Test("Activation monitor does not re-add Finder after migration completes")
    func activationMonitorDoesNotReAddFinderAfterMigration() {
        let suiteName = UUID().uuidString
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(["com.apple.TextEdit"], forKey: "com.comtab.excludedBundleIDs")
        defaults.set(true, forKey: "com.comtab.defaultExcludedBundlesMigrated")

        let monitor = ActivationMonitor(
            notificationCenter: NotificationCenter(),
            workspace: .shared,
            defaults: defaults,
            reopenStatsStore: ReopenStatsStore(defaults: defaults, storageKey: "test.reopenStats"),
            accessController: AppAccessController(distributionChannel: .direct)
        )

        #expect(monitor.userExcludedBundleIDs == ["com.apple.TextEdit"])
        #expect(!monitor.userExcludedBundleIDs.contains("com.apple.finder"))
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
    func activationMonitorReopenCompletionStats() async {
        let suiteName = UUID().uuidString
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let statsStore = ReopenStatsStore(defaults: defaults, storageKey: "test.reopenStats")
        let monitor = ActivationMonitor(
            notificationCenter: NotificationCenter(),
            workspace: .shared,
            defaults: defaults,
            reopenStatsStore: statsStore,
            accessController: AppAccessController(distributionChannel: .direct)
        )

        monitor.handleReopenCompletion(
            requestedBundleID: "com.apple.TextEdit",
            openedBundleID: nil,
            localizedName: nil,
            openedProcessIdentifier: nil,
            error: NSError(domain: "Test", code: 1)
        )
        await Task.yield()
        #expect(statsStore.totalSuccessfulReopens == 0)

        monitor.handleReopenCompletion(
            requestedBundleID: "com.apple.TextEdit",
            openedBundleID: "com.apple.TextEdit",
            localizedName: "TextEdit",
            openedProcessIdentifier: 123,
            error: nil
        )
        await Task.yield()
        #expect(statsStore.totalSuccessfulReopens == 1)
        #expect(statsStore.appStats == [.init(bundleID: "com.apple.TextEdit", displayName: "TextEdit", count: 1)])
    }
}

struct ProStatusManagerTests {
    @MainActor
    private func makeDefaults(suiteName: String = UUID().uuidString) -> (UserDefaults, String) {
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }

    @MainActor
    @Test("Pro status manager does not auto-start trial on first refresh")
    func proStatusDoesNotAutoStartTrial() async {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let mockService = MockRevenueCatService()
        let legacyTracker = MockLegacyAppPurchaseTracker()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let manager = ProStatusManager(
            defaults: defaults,
            revenueCatService: mockService,
            legacyAppPurchaseTracker: legacyTracker,
            now: { now }
        )

        await manager.refresh()

        #expect(manager.status == .expired)
        #expect(defaults.object(forKey: "com.comtab.trialStartDate") as? Date == nil)
        #expect(!manager.shouldOpenProSettings)
    }

    @MainActor
    @Test("Pro status manager starts trial only after onboarding continues")
    func proStatusStartsTrialAfterOnboarding() async {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let manager = ProStatusManager(
            defaults: defaults,
            revenueCatService: MockRevenueCatService(),
            legacyAppPurchaseTracker: MockLegacyAppPurchaseTracker(),
            now: { now }
        )

        await manager.startTrial()

        #expect(defaults.bool(forKey: "com.comtab.hasSeenOnboarding"))
        #expect(defaults.object(forKey: "com.comtab.trialStartDate") as? Date == now)
        #expect(manager.status == .trial(daysRemaining: 7, expiresAt: now.addingTimeInterval(7 * 24 * 60 * 60)))
    }

    @MainActor
    @Test("Pro status manager marks expired trials as inactive")
    func proStatusExpiresTrial() async {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        defaults.set(now.addingTimeInterval(-(8 * 24 * 60 * 60)), forKey: "com.comtab.trialStartDate")

        let manager = ProStatusManager(
            defaults: defaults,
            revenueCatService: MockRevenueCatService(),
            legacyAppPurchaseTracker: MockLegacyAppPurchaseTracker(),
            now: { now }
        )

        await manager.refresh()

        #expect(manager.status == .expired)
        #expect(!manager.status.isActive)
    }

    @MainActor
    @Test("Trial keeps one day remaining until the final second")
    func proStatusTrialRoundsUpRemainingDay() async {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        defaults.set(now.addingTimeInterval(-((6 * 24 * 60 * 60) + 1)), forKey: "com.comtab.trialStartDate")

        let manager = ProStatusManager(
            defaults: defaults,
            revenueCatService: MockRevenueCatService(),
            legacyAppPurchaseTracker: MockLegacyAppPurchaseTracker(),
            now: { now }
        )

        await manager.refresh()

        #expect(manager.status == .trial(daysRemaining: 1, expiresAt: now.addingTimeInterval((24 * 60 * 60) - 1)))
    }

    @MainActor
    @Test("Trial expires exactly at the seven day boundary")
    func proStatusExpiresAtExactBoundary() async {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        defaults.set(now.addingTimeInterval(-(7 * 24 * 60 * 60)), forKey: "com.comtab.trialStartDate")

        let manager = ProStatusManager(
            defaults: defaults,
            revenueCatService: MockRevenueCatService(),
            legacyAppPurchaseTracker: MockLegacyAppPurchaseTracker(),
            now: { now }
        )

        await manager.refresh()

        #expect(manager.status == .expired)
    }

    @MainActor
    @Test("Active lifetime entitlement overrides an expired trial")
    func lifetimeEntitlementOverridesTrial() async {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        defaults.set(now.addingTimeInterval(-(8 * 24 * 60 * 60)), forKey: "com.comtab.trialStartDate")

        let mockService = MockRevenueCatService()
        mockService.cachedEntitlementSnapshot = .init(plan: .lifetime, expirationDate: nil, willRenew: false)
        let legacyTracker = MockLegacyAppPurchaseTracker()

        let manager = ProStatusManager(
            defaults: defaults,
            revenueCatService: mockService,
            legacyAppPurchaseTracker: legacyTracker,
            now: { now }
        )

        manager.configureIfNeeded()

        #expect(manager.status == .pro(plan: .lifetime, expirationDate: nil, willRenew: false))
        #expect(manager.status.isActive)
    }

    @MainActor
    @Test("Delegate customer info updates are reflected in status")
    func delegateUpdatesStatus() async {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let mockService = MockRevenueCatService()
        let legacyTracker = MockLegacyAppPurchaseTracker()
        let manager = ProStatusManager(
            defaults: defaults,
            revenueCatService: mockService,
            legacyAppPurchaseTracker: legacyTracker,
            now: { now }
        )

        manager.configureIfNeeded()
        mockService.customerInfoDidChange?(
            .init(
                plan: .yearly,
                expirationDate: now.addingTimeInterval(365 * 24 * 60 * 60),
                willRenew: true
            )
        )

        #expect(
            manager.status == .pro(
                plan: .yearly,
                expirationDate: now.addingTimeInterval(365 * 24 * 60 * 60),
                willRenew: true
            )
        )
    }

    @MainActor
    @Test("Active yearly entitlement overrides an expired trial")
    func yearlyEntitlementOverridesTrial() async {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let expirationDate = now.addingTimeInterval(365 * 24 * 60 * 60)
        defaults.set(now.addingTimeInterval(-(8 * 24 * 60 * 60)), forKey: "com.comtab.trialStartDate")

        let mockService = MockRevenueCatService()
        mockService.cachedEntitlementSnapshot = .init(plan: .yearly, expirationDate: expirationDate, willRenew: true)
        let legacyTracker = MockLegacyAppPurchaseTracker()

        let manager = ProStatusManager(
            defaults: defaults,
            revenueCatService: mockService,
            legacyAppPurchaseTracker: legacyTracker,
            now: { now }
        )

        manager.configureIfNeeded()

        #expect(manager.status == .pro(plan: .yearly, expirationDate: expirationDate, willRenew: true))
        #expect(manager.status.isActive)
    }

    @MainActor
    @Test("Purchase failures surface through lastError")
    func purchaseFailureUpdatesLastError() async {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let mockService = MockRevenueCatService()
        mockService.purchaseError = ProPurchaseError.network
        let legacyTracker = MockLegacyAppPurchaseTracker()

        let manager = ProStatusManager(
            defaults: defaults,
            revenueCatService: mockService,
            legacyAppPurchaseTracker: legacyTracker,
            now: { now }
        )

        await #expect(throws: ProPurchaseError.network) {
            try await manager.purchase(.yearly)
        }
        #expect(manager.lastError == .network)
        #expect(manager.paywallErrorMessage == ProPurchaseError.network.errorDescription)
    }

    @MainActor
    @Test("Cancelled purchases stay silent in the paywall")
    func purchaseCancelledClearsPaywallError() async {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let mockService = MockRevenueCatService()
        mockService.purchaseError = ProPurchaseError.purchaseCancelled
        let legacyTracker = MockLegacyAppPurchaseTracker()

        let manager = ProStatusManager(
            defaults: defaults,
            revenueCatService: mockService,
            legacyAppPurchaseTracker: legacyTracker,
            now: { now }
        )

        await #expect(throws: ProPurchaseError.purchaseCancelled) {
            try await manager.purchase(.yearly)
        }

        #expect(manager.lastError == .purchaseCancelled)
        #expect(manager.paywallErrorMessage == nil)
    }

    @MainActor
    @Test("Available plans fall back when offering metadata is unavailable")
    func availablePlansFallback() {
        let plans = ProStatusManager.makeAvailablePlans(packageMetadata: nil)

        #expect(plans == ProPlanProduct.fallbackPlans)
    }

    @MainActor
    @Test("Available plans mark missing offerings as unavailable")
    func availablePlansMarkUnavailable() {
        let plans = ProStatusManager.makeAvailablePlans(packageMetadata: [
            .yearly: .init(displayPrice: "$5.99", billingDetail: "per year", isAvailable: true)
        ])

        #expect(plans.first(where: { $0.plan == .yearly })?.isAvailable == true)
        #expect(plans.first(where: { $0.plan == .yearly })?.displayPrice == "$5.99")
        #expect(plans.first(where: { $0.plan == .lifetime })?.isAvailable == false)
    }

    @MainActor
    @Test("Network failures keep fallback plans available")
    func networkFailureKeepsFallbackPlansAvailable() async {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let mockService = MockRevenueCatService()
        mockService.offeringsError = ProPurchaseError.network

        let manager = ProStatusManager(
            defaults: defaults,
            revenueCatService: mockService,
            legacyAppPurchaseTracker: MockLegacyAppPurchaseTracker()
        )

        await manager.loadOfferings()

        #expect(manager.availablePlans.allSatisfy { $0.isAvailable })
        #expect(manager.planProduct(for: .yearly).displayPrice == "$5.99")
        #expect(manager.planProduct(for: .lifetime).displayPrice == "$10.99")
    }

    @MainActor
    @Test("Refresh resolves entitlements without blocking on offerings")
    func refreshOnlyResolvesEntitlements() async {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let mockService = MockRevenueCatService()
        mockService.fetchedEntitlementSnapshot = .init(plan: .lifetime, expirationDate: nil, willRenew: false)

        let manager = ProStatusManager(
            defaults: defaults,
            revenueCatService: mockService,
            legacyAppPurchaseTracker: MockLegacyAppPurchaseTracker()
        )

        await manager.refresh()

        #expect(mockService.fetchCurrentOfferingCallCount == 0)
        #expect(mockService.fetchEntitlementSnapshotCallCount == 1)
        #expect(manager.status == .pro(plan: .lifetime, expirationDate: nil, willRenew: false))
    }

    @MainActor
    @Test("Purchase loading state is set while a purchase is in flight")
    func purchaseLoadingState() async throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let mockService = MockRevenueCatService()
        mockService.purchaseDelayNanoseconds = 100_000_000
        mockService.purchaseSnapshot = .init(
            plan: .yearly,
            expirationDate: now.addingTimeInterval(365 * 24 * 60 * 60),
            willRenew: true
        )
        let legacyTracker = MockLegacyAppPurchaseTracker()

        let manager = ProStatusManager(
            defaults: defaults,
            revenueCatService: mockService,
            legacyAppPurchaseTracker: legacyTracker,
            now: { now }
        )

        let task = Task {
            try await manager.purchase(.yearly)
        }

        await Task.yield()

        #expect(manager.purchaseInProgressPlan == .yearly)

        try await task.value

        #expect(manager.purchaseInProgressPlan == nil)
        #expect(manager.status.isPro)
    }

    @MainActor
    @Test("Restore loading state is set while restore is in flight")
    func restoreLoadingState() async throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let mockService = MockRevenueCatService()
        mockService.restoreDelayNanoseconds = 100_000_000
        mockService.restoreSnapshot = .init(plan: .lifetime, expirationDate: nil, willRenew: false)
        let legacyTracker = MockLegacyAppPurchaseTracker()

        let manager = ProStatusManager(
            defaults: defaults,
            revenueCatService: mockService,
            legacyAppPurchaseTracker: legacyTracker,
            now: { now }
        )

        let task = Task {
            try await manager.restorePurchases()
        }

        await Task.yield()

        #expect(manager.isRestoringPurchases)

        try await task.value

        #expect(!manager.isRestoringPurchases)
        #expect(manager.status == .pro(plan: .lifetime, expirationDate: nil, willRenew: false))
    }

    @MainActor
    @Test("Restore with no previous purchase shows feedback and skips retry")
    func restoreNoPurchaseShowsFeedback() async throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let mockService = MockRevenueCatService()
        mockService.restoreSnapshot = nil
        let legacyTracker = MockLegacyAppPurchaseTracker()

        let manager = ProStatusManager(
            defaults: defaults,
            revenueCatService: mockService,
            legacyAppPurchaseTracker: legacyTracker,
            now: { now }
        )

        try await manager.restorePurchases()

        #expect(!manager.isRestoringPurchases)
        #expect(!manager.status.isPro)
        #expect(manager.paywallErrorMessage == "No active purchase found on this account.")
        #expect(mockService.fetchEntitlementSnapshotCallCount == 0)
    }

    @MainActor
    @Test("Purchase retries entitlement refresh until RevenueCat catches up")
    func purchaseRetriesEntitlementRefresh() async throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let expirationDate = now.addingTimeInterval(365 * 24 * 60 * 60)
        defaults.set(now.addingTimeInterval(-(8 * 24 * 60 * 60)), forKey: "com.comtab.trialStartDate")

        let mockService = MockRevenueCatService()
        mockService.purchaseSnapshot = nil
        mockService.fetchedEntitlementSnapshots = [
            nil,
            nil,
            .init(plan: .yearly, expirationDate: expirationDate, willRenew: true)
        ]
        let legacyTracker = MockLegacyAppPurchaseTracker()

        let manager = ProStatusManager(
            defaults: defaults,
            revenueCatService: mockService,
            legacyAppPurchaseTracker: legacyTracker,
            now: { now }
        )

        try await manager.purchase(.yearly)

        #expect(mockService.fetchEntitlementSnapshotCallCount == 3)
        #expect(manager.status == .pro(plan: .yearly, expirationDate: expirationDate, willRenew: true))
        #expect(manager.lastError == nil)
    }

    @MainActor
    @Test("Purchase surfaces an error when entitlement sync never unlocks Pro")
    func purchaseReportsActivationSyncFailure() async {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        defaults.set(now.addingTimeInterval(-(8 * 24 * 60 * 60)), forKey: "com.comtab.trialStartDate")

        let mockService = MockRevenueCatService()
        mockService.purchaseSnapshot = nil
        mockService.fetchedEntitlementSnapshots = [nil, nil, nil]
        let legacyTracker = MockLegacyAppPurchaseTracker()

        let manager = ProStatusManager(
            defaults: defaults,
            revenueCatService: mockService,
            legacyAppPurchaseTracker: legacyTracker,
            now: { now }
        )

        await #expect(throws: ProPurchaseError.activationPending) {
            try await manager.purchase(.yearly)
        }

        #expect(mockService.fetchEntitlementSnapshotCallCount == 3)
        #expect(manager.lastError == .activationPending)
        #expect(manager.paywallErrorMessage == ProPurchaseError.activationPending.errorDescription)
        #expect(manager.status == .expired)
    }

    @MainActor
    @Test("Expired prompt is raised once per app session")
    func expiredPromptRaisedOncePerSession() async {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        defaults.set(true, forKey: "com.comtab.hasSeenOnboarding")
        defaults.set(now.addingTimeInterval(-(8 * 24 * 60 * 60)), forKey: "com.comtab.trialStartDate")

        let manager = ProStatusManager(
            defaults: defaults,
            revenueCatService: MockRevenueCatService(),
            legacyAppPurchaseTracker: MockLegacyAppPurchaseTracker(),
            now: { now }
        )

        await manager.refresh()
        #expect(manager.shouldOpenProSettings)

        manager.markExpiredPromptHandled()
        #expect(!manager.shouldOpenProSettings)

        await manager.refresh()
        #expect(!manager.shouldOpenProSettings)
    }

    @MainActor
    @Test("Bootstrap with an expired trial does not auto-open Pro settings")
    func bootstrapExpiredDoesNotPrompt() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        defaults.set(now.addingTimeInterval(-(8 * 24 * 60 * 60)), forKey: "com.comtab.trialStartDate")

        let manager = ProStatusManager(
            defaults: defaults,
            revenueCatService: MockRevenueCatService(),
            legacyAppPurchaseTracker: MockLegacyAppPurchaseTracker(),
            now: { now }
        )

        manager.configureIfNeeded()

        #expect(manager.status == .expired)
        #expect(!manager.shouldOpenProSettings)
    }

    @MainActor
    @Test("Expired state prompts after onboarding has already been seen")
    func expiredPromptAppearsAfterOnboarding() async {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(true, forKey: "com.comtab.hasSeenOnboarding")

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let manager = ProStatusManager(
            defaults: defaults,
            revenueCatService: MockRevenueCatService(),
            legacyAppPurchaseTracker: MockLegacyAppPurchaseTracker(),
            now: { now }
        )

        await manager.refresh()

        #expect(manager.status == .expired)
        #expect(manager.shouldOpenProSettings)
        #expect(defaults.object(forKey: "com.comtab.trialStartDate") as? Date == nil)
    }

    @MainActor
    @Test("Network failures fail open instead of restricting core features")
    func networkFailuresFailOpen() async {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(true, forKey: "com.comtab.hasSeenOnboarding")

        let networkError = NSError(
            domain: RevenueCat.ErrorCode.errorDomain,
            code: RevenueCat.ErrorCode.networkError.rawValue
        )
        let mockService = MockRevenueCatService()
        mockService.entitlementError = networkError

        let manager = ProStatusManager(
            defaults: defaults,
            revenueCatService: mockService,
            legacyAppPurchaseTracker: MockLegacyAppPurchaseTracker()
        )
        let source = ProCommerceStateSource(proStatusManager: manager)
        let controller = AppAccessController(
            distributionChannel: .appStore,
            commerceStateSource: source
        )

        await manager.refresh()

        #expect(manager.status == .expired)
        #expect(manager.lastError == .network)
        #expect(source.entitlementState == .trial)
        #expect(controller.isCoreFeatureAvailable)
        #expect(controller.showsUpgradeEntry)
        #expect(!manager.shouldOpenProSettings)
    }

    @Test("Yearly renewal state reports a renewing subscription")
    func yearlyRenewalStateRenews() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let expirationDate = now.addingTimeInterval((12 * 24 * 60 * 60) - 60)
        let status = ProStatus.pro(plan: .yearly, expirationDate: expirationDate, willRenew: true)

        guard case .renews(let resolvedDate, let daysRemaining) = status.renewalState(now: now) else {
            Issue.record("Expected a renewing yearly state.")
            return
        }

        #expect(resolvedDate == expirationDate)
        #expect(daysRemaining == 12)
    }

    @Test("Yearly renewal state reports a non-renewing subscription")
    func yearlyRenewalStateEnds() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let expirationDate = now.addingTimeInterval((2 * 24 * 60 * 60) - 60)
        let status = ProStatus.pro(plan: .yearly, expirationDate: expirationDate, willRenew: false)

        guard case .ends(let resolvedDate, let daysRemaining) = status.renewalState(now: now) else {
            Issue.record("Expected a non-renewing yearly state.")
            return
        }

        #expect(resolvedDate == expirationDate)
        #expect(daysRemaining == 2)
    }

    @MainActor
    @Test("Grandfathered paid-app customers before 1.2.0 unlock lifetime pro")
    func legacyPaidCustomersUnlockLifetime() async {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(true, forKey: "com.comtab.hasSeenOnboarding")

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let purchaseDate = now.addingTimeInterval(-(30 * 24 * 60 * 60))
        let legacyTracker = MockLegacyAppPurchaseTracker()
        legacyTracker.refreshedLegacyAppPurchaseSnapshot = .init(
            originalAppVersion: "1.1.0",
            originalPurchaseDate: purchaseDate
        )

        let manager = ProStatusManager(
            defaults: defaults,
            revenueCatService: MockRevenueCatService(),
            legacyAppPurchaseTracker: legacyTracker,
            now: { now }
        )

        await manager.refresh()

        #expect(manager.status == .pro(plan: .lifetime, expirationDate: nil, willRenew: false))
        #expect(manager.currentEntitlementSnapshot == .init(
            plan: .lifetime,
            expirationDate: nil,
            willRenew: false,
            originalPurchaseDate: purchaseDate
        ))
    }

    @MainActor
    @Test("Free downloads at 1.2.0 or later are not grandfathered")
    func currentFreeDownloadsAreNotGrandfathered() async {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(true, forKey: "com.comtab.hasSeenOnboarding")

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let legacyTracker = MockLegacyAppPurchaseTracker()
        legacyTracker.refreshedLegacyAppPurchaseSnapshot = .init(
            originalAppVersion: "1.2.0",
            originalPurchaseDate: now.addingTimeInterval(-(2 * 24 * 60 * 60))
        )

        let manager = ProStatusManager(
            defaults: defaults,
            revenueCatService: MockRevenueCatService(),
            legacyAppPurchaseTracker: legacyTracker,
            now: { now }
        )

        await manager.refresh()

        #expect(manager.status == .expired)
        #expect(manager.currentEntitlementSnapshot == nil)
    }
}

@MainActor
struct RevenueCatSnapshotParserTests {
    private let originalPurchaseDate = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeEntitlement(
        identifier: String,
        isActive: Bool,
        productIdentifier: String,
        expirationDate: Date?,
        willRenew: Bool? = nil
    ) -> EntitlementInfo {
        .init(
            identifier: identifier,
            isActive: isActive,
            willRenew: willRenew ?? (expirationDate != nil),
            periodType: .normal,
            latestPurchaseDate: originalPurchaseDate,
            originalPurchaseDate: originalPurchaseDate,
            expirationDate: expirationDate,
            store: .macAppStore,
            productIdentifier: productIdentifier,
            isSandbox: true,
            ownershipType: .purchased
        )
    }

    private func makeCustomerInfo(entitlements: [EntitlementInfo]) -> CustomerInfo {
        let requestDate = Date(timeIntervalSince1970: 1_700_000_100)
        let entitlementsByIdentifier = Dictionary(uniqueKeysWithValues: entitlements.map { ($0.identifier, $0) })
        let expirationDatesByProductId: [String: Date] = Dictionary(
            uniqueKeysWithValues: entitlements.compactMap { entitlement in
                guard let expirationDate = entitlement.expirationDate else {
                    return nil
                }

                return (entitlement.productIdentifier, expirationDate)
            }
        )
        let purchaseDatesByProductId: [String: Date] = Dictionary(
            uniqueKeysWithValues: entitlements.compactMap { entitlement in
                guard let latestPurchaseDate = entitlement.latestPurchaseDate else {
                    return nil
                }

                return (entitlement.productIdentifier, latestPurchaseDate)
            }
        )

        return .init(
            entitlements: .init(entitlements: entitlementsByIdentifier),
            expirationDatesByProductId: expirationDatesByProductId,
            purchaseDatesByProductId: purchaseDatesByProductId,
            allPurchasedProductIds: Set(entitlements.map(\.productIdentifier)),
            requestDate: requestDate,
            firstSeen: requestDate,
            originalAppUserId: "test-user"
        )
    }

    @Test("RevenueCat parser prefers the configured entitlement identifier")
    func parserUsesConfiguredEntitlementIdentifier() {
        let expirationDate = Date(timeIntervalSince1970: 1_800_000_000)
        let customerInfo = makeCustomerInfo(entitlements: [
            makeEntitlement(
                identifier: RevenueCatConfiguration.entitlementIdentifier,
                isActive: true,
                productIdentifier: RevenueCatConfiguration.lifetimeProductIdentifier,
                expirationDate: nil
            ),
            makeEntitlement(
                identifier: "other",
                isActive: true,
                productIdentifier: RevenueCatConfiguration.yearlyProductIdentifier,
                expirationDate: expirationDate
            )
        ])

        let snapshot = RevenueCatSnapshotParser.makeEntitlementSnapshot(from: customerInfo)

        #expect(snapshot == .init(plan: .lifetime, expirationDate: nil, willRenew: false, originalPurchaseDate: originalPurchaseDate))
    }

    @Test("RevenueCat parser falls back to active product identifiers when entitlement id is missing")
    func parserFallsBackToProductIdentifier() {
        let expirationDate = Date(timeIntervalSince1970: 1_800_000_000)
        let customerInfo = makeCustomerInfo(entitlements: [
            makeEntitlement(
                identifier: "fallback-yearly",
                isActive: true,
                productIdentifier: RevenueCatConfiguration.yearlyProductIdentifier,
                expirationDate: expirationDate
            )
        ])

        let snapshot = RevenueCatSnapshotParser.makeEntitlementSnapshot(from: customerInfo)

        #expect(snapshot == .init(plan: .yearly, expirationDate: expirationDate, willRenew: true, originalPurchaseDate: originalPurchaseDate))
    }

    @Test("RevenueCat parser falls back to any active entitlement when identifiers drift")
    func parserFallsBackToGenericActiveEntitlement() {
        let expirationDate = Date(timeIntervalSince1970: 1_800_000_000)
        let customerInfo = makeCustomerInfo(entitlements: [
            makeEntitlement(
                identifier: "promo-pro",
                isActive: true,
                productIdentifier: "com.dev.kkuk.CommandReopen.promo",
                expirationDate: expirationDate
            )
        ])

        let snapshot = RevenueCatSnapshotParser.makeEntitlementSnapshot(from: customerInfo)

        #expect(snapshot == .init(plan: .yearly, expirationDate: expirationDate, willRenew: true, originalPurchaseDate: originalPurchaseDate))
    }

    @Test("RevenueCat parser ignores inactive configured entitlements")
    func parserIgnoresInactiveConfiguredEntitlement() {
        let customerInfo = makeCustomerInfo(entitlements: [
            makeEntitlement(
                identifier: RevenueCatConfiguration.entitlementIdentifier,
                isActive: false,
                productIdentifier: RevenueCatConfiguration.yearlyProductIdentifier,
                expirationDate: Date(timeIntervalSince1970: 1_800_000_000)
            )
        ])

        let snapshot = RevenueCatSnapshotParser.makeEntitlementSnapshot(from: customerInfo)

        #expect(snapshot == nil)
    }

    @Test("RevenueCat parser infers lifetime for unknown products without expiration")
    func parserInfersLifetimeWithoutExpirationDate() {
        let customerInfo = makeCustomerInfo(entitlements: [
            makeEntitlement(
                identifier: RevenueCatConfiguration.entitlementIdentifier,
                isActive: true,
                productIdentifier: "custom.product",
                expirationDate: nil
            )
        ])

        let snapshot = RevenueCatSnapshotParser.makeEntitlementSnapshot(from: customerInfo)

        #expect(snapshot == .init(plan: .lifetime, expirationDate: nil, willRenew: false, originalPurchaseDate: originalPurchaseDate))
    }

    @Test("RevenueCat parser infers yearly for unknown products with expiration")
    func parserInfersYearlyWithExpirationDate() {
        let expirationDate = Date(timeIntervalSince1970: 1_800_000_000)
        let customerInfo = makeCustomerInfo(entitlements: [
            makeEntitlement(
                identifier: RevenueCatConfiguration.entitlementIdentifier,
                isActive: true,
                productIdentifier: "custom.subscription",
                expirationDate: expirationDate
            )
        ])

        let snapshot = RevenueCatSnapshotParser.makeEntitlementSnapshot(from: customerInfo)

        #expect(snapshot == .init(plan: .yearly, expirationDate: expirationDate, willRenew: true, originalPurchaseDate: originalPurchaseDate))
    }

    @Test("RevenueCat parser preserves cancelled yearly renewals")
    func parserPreservesCancelledYearlyRenewalState() {
        let expirationDate = Date(timeIntervalSince1970: 1_800_000_000)
        let customerInfo = makeCustomerInfo(entitlements: [
            makeEntitlement(
                identifier: RevenueCatConfiguration.entitlementIdentifier,
                isActive: true,
                productIdentifier: RevenueCatConfiguration.yearlyProductIdentifier,
                expirationDate: expirationDate,
                willRenew: false
            )
        ])

        let snapshot = RevenueCatSnapshotParser.makeEntitlementSnapshot(from: customerInfo)

        #expect(snapshot == .init(plan: .yearly, expirationDate: expirationDate, willRenew: false, originalPurchaseDate: originalPurchaseDate))
    }
}

struct ProPurchaseErrorTests {
    @Test("RevenueCat configuration errors map to not configured")
    func configurationErrorMapsToNotConfigured() {
        let error = NSError(
            domain: RevenueCat.ErrorCode.errorDomain,
            code: RevenueCat.ErrorCode.configurationError.rawValue
        )

        #expect(ProPurchaseError(error: error) == .notConfigured)
    }

    @Test("RevenueCat invalid receipt errors map to invalid receipt")
    func invalidReceiptMapsToInvalidReceipt() {
        let error = NSError(
            domain: RevenueCat.ErrorCode.errorDomain,
            code: RevenueCat.ErrorCode.invalidReceiptError.rawValue
        )

        #expect(ProPurchaseError(error: error) == .invalidReceipt)
    }

    @Test("Non-RevenueCat domains do not get remapped by raw code alone")
    func unrelatedDomainStaysUnknown() {
        let error = NSError(
            domain: NSCocoaErrorDomain,
            code: RevenueCat.ErrorCode.configurationError.rawValue,
            userInfo: [NSLocalizedDescriptionKey: "Cocoa failure"]
        )

        #expect(ProPurchaseError(error: error) == .unknown("Cocoa failure"))
    }
}

struct AppAccessControllerTests {
    @MainActor
    @Test("Direct access controller keeps core feature unlocked and shows support tab only")
    func directAccessControllerDefaults() {
        let controller = AppAccessController(distributionChannel: .direct)

        #expect(controller.isCoreFeatureAvailable)
        #expect(controller.showsProTab)
        #expect(!controller.showsUpgradeEntry)
        #expect(!controller.shouldShowOnboarding)
    }

    @MainActor
    @Test("MAS access controller reflects commerce state updates")
    func masAccessControllerUpdates() {
        let source = MockCommerceStateSource(
            entitlementState: .trial,
            isFirstLaunch: true
        )
        let controller = AppAccessController(
            distributionChannel: .appStore,
            commerceStateSource: source
        )

        #expect(controller.isCoreFeatureAvailable)
        #expect(controller.showsProTab)
        #expect(controller.showsUpgradeEntry)
        #expect(controller.shouldShowOnboarding)

        source.update(entitlementState: .expired)
        #expect(!controller.isCoreFeatureAvailable)
        #expect(controller.showsUpgradeEntry)

        source.update(entitlementState: .pro)
        #expect(controller.isCoreFeatureAvailable)
        #expect(!controller.showsUpgradeEntry)
        #expect(controller.shouldShowOnboarding)
    }

    @MainActor
    @Test("MAS onboarding depends on first-launch state only")
    func masOnboardingDependsOnFirstLaunch() {
        let source = MockCommerceStateSource(
            entitlementState: .pro,
            isFirstLaunch: true
        )
        let controller = AppAccessController(
            distributionChannel: .appStore,
            commerceStateSource: source
        )

        #expect(controller.shouldShowOnboarding)

        source.isFirstLaunch = false
        #expect(!controller.shouldShowOnboarding)
    }

    @MainActor
    @Test("MAS access controller forwards pro settings prompt state")
    func masAccessControllerPromptHandling() {
        let source = MockCommerceStateSource(
            entitlementState: .expired,
            shouldOpenProSettings: true
        )
        let controller = AppAccessController(
            distributionChannel: .appStore,
            commerceStateSource: source
        )

        #expect(controller.shouldOpenProSettings)

        controller.markPromptHandled()

        #expect(!controller.shouldOpenProSettings)
        #expect(!source.shouldOpenProSettings)
    }
}

struct LegacyAppStoreReceiptParserTests {
    @Test("Receipt parser extracts original app version from payload")
    func receiptParserExtractsOriginalAppVersion() throws {
        let payload = makeReceiptPayload(originalAppVersion: "1.1.0")

        let receipt = try LegacyAppStoreReceiptParser.parse(payloadData: payload)

        #expect(receipt == .init(originalAppVersion: "1.1.0"))
    }

    @Test("Receipt parser rejects payloads without original app version")
    func receiptParserRequiresOriginalAppVersion() throws {
        let payload = wrap(tag: 0x31, content: Data())

        do {
            _ = try LegacyAppStoreReceiptParser.parse(payloadData: payload)
            Issue.record("Expected parser to reject payloads without original app version.")
        } catch let error as ReceiptDecodingError {
            #expect(error == .missingOriginalAppVersion)
        }
    }

    private func makeReceiptPayload(originalAppVersion: String) -> Data {
        let value = wrap(tag: 0x04, content: wrap(tag: 0x0C, content: Data(originalAppVersion.utf8)))
        let attribute = wrap(
            tag: 0x30,
            content: encodeInteger(19) + encodeInteger(1) + value
        )

        return wrap(tag: 0x31, content: attribute)
    }

    private func encodeInteger(_ value: Int) -> Data {
        wrap(tag: 0x02, content: Data([UInt8(value)]))
    }

    private func wrap(tag: UInt8, content: Data) -> Data {
        Data([tag]) + encodeLength(content.count) + content
    }

    private func encodeLength(_ length: Int) -> Data {
        if length < 0x80 {
            return Data([UInt8(length)])
        }

        let bytes = withUnsafeBytes(of: UInt32(length).bigEndian) { rawBuffer in
            Data(rawBuffer.drop { $0 == 0 })
        }

        return Data([0x80 | UInt8(bytes.count)]) + bytes
    }
}

struct SettingsAndStatusBarPresentationTests {
    @MainActor
    @Test("Settings tabs can include support or Pro tab")
    func settingsTabsForDirect() {
        #expect(SettingsTab.visibleTabs(showProTab: true) == [.general, .statistics, .pro])
        #expect(SettingsTab.pro.title(for: .direct) == "Support")
        #expect(SettingsTab.pro.title(for: .appStore) == "Pro")
    }

    @MainActor
    @Test("Status bar presentation follows access controller state")
    func statusBarPresentation() {
        let directController = AppAccessController(distributionChannel: .direct)
        #expect(StatusBarController.presentation(for: directController) == .init(
            showsUpgradeItem: false,
            canToggleAutoReopen: true
        ))

        let source = MockCommerceStateSource(entitlementState: .expired)
        let masController = AppAccessController(
            distributionChannel: .appStore,
            commerceStateSource: source
        )
        #expect(StatusBarController.presentation(for: masController) == .init(
            showsUpgradeItem: true,
            canToggleAutoReopen: false
        ))
    }
}
