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
    var fetchEntitlementSnapshotCallCount = 0
    var purchaseDelayNanoseconds: UInt64?
    var restoreDelayNanoseconds: UInt64?

    func configureIfNeeded() {
        configureCallCount += 1
    }

    func fetchCurrentOffering() async throws -> Offering? {
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
    @Test("Pro status manager starts a seven day trial on first refresh")
    func proStatusStartsTrial() async {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let mockService = MockRevenueCatService()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let manager = ProStatusManager(
            defaults: defaults,
            revenueCatService: mockService,
            now: { now },
            trialStartDateProvider: { now }
        )

        await manager.refresh()

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
            now: { now },
            trialStartDateProvider: { now }
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
            now: { now },
            trialStartDateProvider: { now }
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
            now: { now },
            trialStartDateProvider: { now }
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

        let manager = ProStatusManager(
            defaults: defaults,
            revenueCatService: mockService,
            now: { now },
            trialStartDateProvider: { now }
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
        let manager = ProStatusManager(
            defaults: defaults,
            revenueCatService: mockService,
            now: { now },
            trialStartDateProvider: { now }
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

        let manager = ProStatusManager(
            defaults: defaults,
            revenueCatService: mockService,
            now: { now },
            trialStartDateProvider: { now }
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

        let manager = ProStatusManager(
            defaults: defaults,
            revenueCatService: mockService,
            now: { now },
            trialStartDateProvider: { now }
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

        let manager = ProStatusManager(
            defaults: defaults,
            revenueCatService: mockService,
            now: { now },
            trialStartDateProvider: { now }
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

        let manager = ProStatusManager(
            defaults: defaults,
            revenueCatService: mockService,
            now: { now },
            trialStartDateProvider: { now }
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

        let manager = ProStatusManager(
            defaults: defaults,
            revenueCatService: mockService,
            now: { now },
            trialStartDateProvider: { now }
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

        let manager = ProStatusManager(
            defaults: defaults,
            revenueCatService: mockService,
            now: { now },
            trialStartDateProvider: { now }
        )

        try await manager.restorePurchases()

        #expect(!manager.isRestoringPurchases)
        #expect(!manager.status.isPro)
        #expect(manager.paywallErrorMessage != nil)
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

        let manager = ProStatusManager(
            defaults: defaults,
            revenueCatService: mockService,
            now: { now },
            trialStartDateProvider: { now }
        )

        try await manager.purchase(.yearly)

        #expect(mockService.fetchEntitlementSnapshotCallCount == 3)
        #expect(manager.status == .pro(plan: .yearly, expirationDate: expirationDate, willRenew: true))
        #expect(manager.lastError == nil)
    }

    @MainActor
    @Test("Expired prompt is raised once per app session")
    func expiredPromptRaisedOncePerSession() async {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        defaults.set(now.addingTimeInterval(-(8 * 24 * 60 * 60)), forKey: "com.comtab.trialStartDate")

        let manager = ProStatusManager(
            defaults: defaults,
            revenueCatService: MockRevenueCatService(),
            now: { now },
            trialStartDateProvider: { now }
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
            now: { now },
            trialStartDateProvider: { now }
        )

        manager.configureIfNeeded()

        #expect(manager.status == .expired)
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
        let error = NSError(domain: "RevenueCat", code: RevenueCat.ErrorCode.configurationError.rawValue)

        #expect(ProPurchaseError(error: error) == .notConfigured)
    }
}

struct AppAccessControllerTests {
    @MainActor
    @Test("Direct access controller keeps core feature unlocked and hides upgrade entry")
    func directAccessControllerDefaults() {
        let controller = AppAccessController(distributionChannel: .direct)

        #expect(controller.isCoreFeatureAvailable)
        #expect(!controller.showsProTab)
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

struct SettingsAndStatusBarPresentationTests {
    @MainActor
    @Test("Settings tabs hide Pro for direct channel")
    func settingsTabsForDirect() {
        #expect(SettingsTab.visibleTabs(showProTab: false) == [.general, .statistics])
        #expect(SettingsTab.visibleTabs(showProTab: true) == [.general, .statistics, .pro])
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
