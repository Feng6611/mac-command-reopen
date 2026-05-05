import Foundation
import RevenueCatCommerceKit
import Testing
@testable import Command_Reopen

struct ProStatusManagerTests {
    @MainActor
    private func makeDefaults(suiteName: String = UUID().uuidString) -> (UserDefaults, String) {
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }

    @MainActor
    @Test("Pro status manager starts trial by default when no local trial exists")
    func proStatusStartsTrialByDefault() async {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let mockService = MockCommerceClient()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let manager = ProStatusManager(
            defaults: defaults,
            commerceClient: mockService,
            now: { now }
        )

        await manager.refresh()

        let expectedExpiresAt = now.addingTimeInterval(2 * 24 * 60 * 60)
        #expect(manager.status == .trial(daysRemaining: 2, expiresAt: expectedExpiresAt))
        #expect(defaults.object(forKey: AppDefaults.RawKey.trialStartDate) as? Date == now)
        #expect(!manager.shouldOpenProSettings)
    }

    @MainActor
    @Test("Get Started marks onboarding without resetting the trial")
    func getStartedMarksOnboardingWithoutResettingTrial() async {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let manager = ProStatusManager(
            defaults: defaults,
            commerceClient: MockCommerceClient(),
            now: { now }
        )

        #expect(!defaults.bool(forKey: AppDefaults.RawKey.hasSeenOnboarding))
        #expect(defaults.object(forKey: AppDefaults.RawKey.trialStartDate) as? Date == now)

        await manager.startTrial()

        #expect(defaults.bool(forKey: AppDefaults.RawKey.hasSeenOnboarding))
        #expect(defaults.object(forKey: AppDefaults.RawKey.trialStartDate) as? Date == now)
        let expectedExpiresAt = now.addingTimeInterval(2 * 24 * 60 * 60)
        #expect(manager.status == .trial(daysRemaining: 2, expiresAt: expectedExpiresAt))
    }

    @MainActor
    @Test("Skipping onboarding marks it seen without resetting the trial")
    func skipOnboardingMarksSeenWithoutResettingTrial() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let manager = ProStatusManager(
            defaults: defaults,
            commerceClient: MockCommerceClient(),
            now: { now }
        )

        manager.finishOnboardingWithoutTrial()

        #expect(defaults.bool(forKey: AppDefaults.RawKey.hasSeenOnboarding))
        #expect(defaults.object(forKey: AppDefaults.RawKey.trialStartDate) as? Date == now)
        let expectedExpiresAt = now.addingTimeInterval(2 * 24 * 60 * 60)
        #expect(manager.status == .trial(daysRemaining: 2, expiresAt: expectedExpiresAt))
    }

    @MainActor
    @Test("Lifetime purchase marks onboarding seen")
    func lifetimePurchaseMarksOnboardingSeen() async throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let mockService = MockCommerceClient()
        mockService.purchaseEntitlement = .init(plan: .lifetime, expirationDate: nil, willRenew: false)
        let manager = ProStatusManager(
            defaults: defaults,
            commerceClient: mockService,
            now: { now }
        )

        try await manager.purchase(.lifetime)

        #expect(defaults.bool(forKey: AppDefaults.RawKey.hasSeenOnboarding))
        #expect(manager.status == .pro(plan: .lifetime, expirationDate: nil, willRenew: false))
    }

    @MainActor
    @Test("Cancelled purchase does not mark onboarding seen")
    func cancelledPurchaseDoesNotMarkOnboardingSeen() async {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let mockService = MockCommerceClient()
        mockService.purchaseError = ProPurchaseError.purchaseCancelled
        let manager = ProStatusManager(
            defaults: defaults,
            commerceClient: mockService,
        )

        await #expect(throws: ProPurchaseError.purchaseCancelled) {
            try await manager.purchase(.lifetime)
        }

        #expect(!defaults.bool(forKey: AppDefaults.RawKey.hasSeenOnboarding))
    }

    @MainActor
    @Test("Pro status manager marks expired trials as inactive")
    func proStatusExpiresTrial() async {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        defaults.set(now.addingTimeInterval(-(8 * 24 * 60 * 60)), forKey: AppDefaults.RawKey.trialStartDate)

        let manager = ProStatusManager(
            defaults: defaults,
            commerceClient: MockCommerceClient(),
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
        defaults.set(now.addingTimeInterval(-((24 * 60 * 60) + 1)), forKey: AppDefaults.RawKey.trialStartDate)

        let manager = ProStatusManager(
            defaults: defaults,
            commerceClient: MockCommerceClient(),
            now: { now }
        )

        await manager.refresh()

        #expect(manager.status == .trial(daysRemaining: 1, expiresAt: now.addingTimeInterval((24 * 60 * 60) - 1)))
    }

    @MainActor
    @Test("Trial expires exactly at the two day boundary")
    func proStatusExpiresAtExactBoundary() async {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        defaults.set(now.addingTimeInterval(-(2 * 24 * 60 * 60)), forKey: AppDefaults.RawKey.trialStartDate)

        let manager = ProStatusManager(
            defaults: defaults,
            commerceClient: MockCommerceClient(),
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
        defaults.set(now.addingTimeInterval(-(8 * 24 * 60 * 60)), forKey: AppDefaults.RawKey.trialStartDate)

        let mockService = MockCommerceClient()
        mockService.cachedEntitlement = .init(plan: .lifetime, expirationDate: nil, willRenew: false)
        let manager = ProStatusManager(
            defaults: defaults,
            commerceClient: mockService,
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
        let mockService = MockCommerceClient()
        let manager = ProStatusManager(
            defaults: defaults,
            commerceClient: mockService,
            now: { now }
        )

        manager.configureIfNeeded()
        mockService.entitlementDidChange?(
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
        defaults.set(now.addingTimeInterval(-(8 * 24 * 60 * 60)), forKey: AppDefaults.RawKey.trialStartDate)

        let mockService = MockCommerceClient()
        mockService.cachedEntitlement = .init(plan: .yearly, expirationDate: expirationDate, willRenew: true)
        let manager = ProStatusManager(
            defaults: defaults,
            commerceClient: mockService,
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
        let mockService = MockCommerceClient()
        mockService.purchaseError = ProPurchaseError.network
        let manager = ProStatusManager(
            defaults: defaults,
            commerceClient: mockService,
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
        let mockService = MockCommerceClient()
        mockService.purchaseError = ProPurchaseError.purchaseCancelled
        let manager = ProStatusManager(
            defaults: defaults,
            commerceClient: mockService,
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

        let mockService = MockCommerceClient()
        mockService.offeringsError = ProPurchaseError.network

        let manager = ProStatusManager(
            defaults: defaults,
            commerceClient: mockService,
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

        let mockService = MockCommerceClient()
        mockService.fetchedEntitlement = .init(plan: .lifetime, expirationDate: nil, willRenew: false)

        let manager = ProStatusManager(
            defaults: defaults,
            commerceClient: mockService,
        )

        await manager.refresh()

        #expect(mockService.loadOfferingCallCount == 0)
        #expect(mockService.refreshEntitlementCallCount == 1)
        #expect(manager.status == .pro(plan: .lifetime, expirationDate: nil, willRenew: false))
    }

    @MainActor
    @Test("Purchase loading state is set while a purchase is in flight")
    func purchaseLoadingState() async throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let mockService = MockCommerceClient()
        mockService.purchaseDelayNanoseconds = 100_000_000
        mockService.purchaseEntitlement = .init(
            plan: .yearly,
            expirationDate: now.addingTimeInterval(365 * 24 * 60 * 60),
            willRenew: true
        )
        let manager = ProStatusManager(
            defaults: defaults,
            commerceClient: mockService,
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
        let mockService = MockCommerceClient()
        mockService.restoreDelayNanoseconds = 100_000_000
        mockService.restoreEntitlement = .init(plan: .lifetime, expirationDate: nil, willRenew: false)
        let manager = ProStatusManager(
            defaults: defaults,
            commerceClient: mockService,
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
        let mockService = MockCommerceClient()
        mockService.restoreEntitlement = nil
        let manager = ProStatusManager(
            defaults: defaults,
            commerceClient: mockService,
            now: { now }
        )

        try await manager.restorePurchases()

        #expect(!manager.isRestoringPurchases)
        #expect(!manager.status.isPro)
        #expect(manager.paywallErrorMessage == "No active purchase found on this account.")
        #expect(mockService.refreshEntitlementCallCount == 0)
    }

    @MainActor
    @Test("Purchase retries entitlement refresh until RevenueCat catches up")
    func purchaseRetriesEntitlementRefresh() async throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let expirationDate = now.addingTimeInterval(365 * 24 * 60 * 60)
        defaults.set(now.addingTimeInterval(-(8 * 24 * 60 * 60)), forKey: AppDefaults.RawKey.trialStartDate)

        let mockService = MockCommerceClient()
        mockService.purchaseEntitlement = nil
        mockService.fetchedEntitlements = [
            nil,
            nil,
            .init(plan: .yearly, expirationDate: expirationDate, willRenew: true)
        ]
        let manager = ProStatusManager(
            defaults: defaults,
            commerceClient: mockService,
            now: { now }
        )

        try await manager.purchase(.yearly)

        #expect(mockService.refreshEntitlementCallCount == 3)
        #expect(manager.status == .pro(plan: .yearly, expirationDate: expirationDate, willRenew: true))
        #expect(manager.lastError == nil)
    }

    @MainActor
    @Test("Purchase surfaces an error when entitlement sync never unlocks Pro")
    func purchaseReportsActivationSyncFailure() async {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        defaults.set(now.addingTimeInterval(-(8 * 24 * 60 * 60)), forKey: AppDefaults.RawKey.trialStartDate)

        let mockService = MockCommerceClient()
        mockService.purchaseEntitlement = nil
        mockService.fetchedEntitlements = [nil, nil, nil]
        let manager = ProStatusManager(
            defaults: defaults,
            commerceClient: mockService,
            now: { now }
        )

        await #expect(throws: ProPurchaseError.activationPending) {
            try await manager.purchase(.yearly)
        }

        #expect(mockService.refreshEntitlementCallCount == 3)
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
        defaults.set(true, forKey: AppDefaults.RawKey.hasSeenOnboarding)
        defaults.set(now.addingTimeInterval(-(8 * 24 * 60 * 60)), forKey: AppDefaults.RawKey.trialStartDate)

        let manager = ProStatusManager(
            defaults: defaults,
            commerceClient: MockCommerceClient(),
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
        defaults.set(now.addingTimeInterval(-(8 * 24 * 60 * 60)), forKey: AppDefaults.RawKey.trialStartDate)

        let manager = ProStatusManager(
            defaults: defaults,
            commerceClient: MockCommerceClient(),
            now: { now }
        )

        manager.configureIfNeeded()

        #expect(manager.status == .expired)
        #expect(!manager.shouldOpenProSettings)
    }

    @MainActor
    @Test("Missing trial date backfills trial even after onboarding has been seen")
    func missingTrialDateBackfillsTrialAfterOnboarding() async {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(true, forKey: AppDefaults.RawKey.hasSeenOnboarding)

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let manager = ProStatusManager(
            defaults: defaults,
            commerceClient: MockCommerceClient(),
            now: { now }
        )

        await manager.refresh()

        let expectedExpiresAt = now.addingTimeInterval(2 * 24 * 60 * 60)
        #expect(manager.status == .trial(daysRemaining: 2, expiresAt: expectedExpiresAt))
        #expect(!manager.shouldOpenProSettings)
        #expect(defaults.object(forKey: AppDefaults.RawKey.trialStartDate) as? Date == now)
    }

    @MainActor
    @Test("Network failures fail open instead of restricting core features")
    func networkFailuresFailOpen() async {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(true, forKey: AppDefaults.RawKey.hasSeenOnboarding)

        let mockService = MockCommerceClient()
        mockService.entitlementError = CommercePurchaseError.network
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        let manager = ProStatusManager(
            defaults: defaults,
            commerceClient: mockService,
            now: { now }
        )
        let source = ProCommerceStateSource(proStatusManager: manager)
        let controller = AppAccessController(
            distributionChannel: .appStore,
            commerceStateSource: source
        )

        await manager.refresh()

        let expectedExpiresAt = now.addingTimeInterval(2 * 24 * 60 * 60)
        #expect(manager.status == .trial(daysRemaining: 2, expiresAt: expectedExpiresAt))
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

        defaults.set(true, forKey: AppDefaults.RawKey.hasSeenOnboarding)

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let purchaseDate = now.addingTimeInterval(-(30 * 24 * 60 * 60))
        let mockCommerce = MockCommerceClient()
        mockCommerce.fetchedEntitlement = .init(
            plan: .lifetime,
            expirationDate: nil,
            willRenew: false,
            originalPurchaseDate: purchaseDate
        )

        let manager = ProStatusManager(
            defaults: defaults,
            commerceClient: mockCommerce,
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
    @Test("Downloads without a commerce entitlement use the local trial")
    func downloadsWithoutCommerceEntitlementUseLocalTrial() async {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(true, forKey: AppDefaults.RawKey.hasSeenOnboarding)

        let now = Date(timeIntervalSince1970: 1_700_000_000)

        let manager = ProStatusManager(
            defaults: defaults,
            commerceClient: MockCommerceClient(),
            now: { now }
        )

        await manager.refresh()

        let expectedExpiresAt = now.addingTimeInterval(2 * 24 * 60 * 60)
        #expect(manager.status == .trial(daysRemaining: 2, expiresAt: expectedExpiresAt))
        #expect(manager.currentEntitlementSnapshot == nil)
    }
}
