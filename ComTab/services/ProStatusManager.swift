//
//  ProStatusManager.swift
//  ComTab
//
//  Created by CHEN on 2026/3/28.
//

import Combine
import Defaults
import Foundation
import os

@MainActor
final class ProStatusManager: ObservableObject {
    enum Constants {
        static let trialDuration: TimeInterval = 2 * 24 * 60 * 60
        static let transactionRefreshAttempts = 3
        static let transactionRefreshDelayNanoseconds: UInt64 = 750_000_000
        static let grandfatheringCutoffVersion = "1.2.0"
    }

    private enum StatusUpdateSource {
        case bootstrap
        case refresh
        case stateChange
    }

    static let shared = ProStatusManager()

    @Published private(set) var status: ProStatus
    @Published private(set) var currentOffering: ProOfferingSnapshot?
    @Published private(set) var availablePlans: [ProPlanProduct]
    @Published private(set) var lastError: ProPurchaseError?
    @Published private(set) var purchaseInProgressPlan: ProPlan?
    @Published private(set) var isRestoringPurchases = false

    var currentEntitlementSnapshot: ProEntitlementSnapshot? {
        Self.resolvedEntitlementSnapshot(
            revenueCatSnapshot: revenueCatEntitlementSnapshot,
            legacySnapshot: legacyAppPurchaseSnapshot
        )
    }
    @Published private(set) var paywallErrorMessage: String?
    @Published private(set) var paywallSuccessMessage: String?
    @Published private(set) var shouldOpenProSettings = false

    private let defaults: UserDefaults
    private let revenueCatService: any RevenueCatServicing
    private let legacyAppPurchaseTracker: any LegacyAppPurchaseChecking
    private let now: () -> Date

    private var revenueCatEntitlementSnapshot: ProEntitlementSnapshot?
    private var legacyAppPurchaseSnapshot: LegacyAppPurchaseSnapshot?
    private var hasConfigured = false
    private var hasCompletedInitialRefresh = false
    private var hasPromptedForExpiredStateThisSession = false

    var isFirstLaunch: Bool {
        !defaults[AppDefaults.hasSeenOnboarding]
    }

    var accessEntitlementState: AccessEntitlementState {
        Self.accessEntitlementState(status: status, lastError: lastError)
    }

    init(
        defaults: UserDefaults = .standard,
        revenueCatService: (any RevenueCatServicing)? = nil,
        legacyAppPurchaseTracker: (any LegacyAppPurchaseChecking)? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        let service = revenueCatService ?? RevenueCatService.shared
        let cachedSnapshot = service.cachedEntitlementSnapshot
        let legacyTracker = legacyAppPurchaseTracker ?? LegacyAppPurchaseTracker.shared
        let cachedLegacySnapshot = legacyTracker.cachedLegacyAppPurchaseSnapshot
        if Self.resolvedEntitlementSnapshot(
            revenueCatSnapshot: cachedSnapshot,
            legacySnapshot: cachedLegacySnapshot
        ) == nil,
           defaults[AppDefaults.trialStartDate] == nil {
            let resolvedStartDate = now()
            defaults[AppDefaults.trialStartDate] = resolvedStartDate
            AppLogger.purchase.notice("Started local trial at \(resolvedStartDate.formatted())")
        }
        self.defaults = defaults
        self.revenueCatService = service
        self.legacyAppPurchaseTracker = legacyTracker
        self.now = now
        self.revenueCatEntitlementSnapshot = cachedSnapshot
        self.legacyAppPurchaseSnapshot = cachedLegacySnapshot
        self.currentOffering = nil
        self.availablePlans = ProPlanProduct.fallbackPlans
        self.lastError = nil
        self.purchaseInProgressPlan = nil
        self.paywallErrorMessage = nil
        self.paywallSuccessMessage = nil
        self.status = Self.computeStatus(entitlementSnapshot: Self.resolvedEntitlementSnapshot(
            revenueCatSnapshot: cachedSnapshot,
            legacySnapshot: self.legacyAppPurchaseSnapshot
        ), defaults: defaults, now: now)
    }

    func configureIfNeeded() {
        guard !hasConfigured else {
            return
        }

        revenueCatService.customerInfoDidChange = { [weak self] snapshot in
            self?.applyEntitlementSnapshot(snapshot, source: .stateChange)
        }
        revenueCatService.configureIfNeeded()
        revenueCatEntitlementSnapshot = revenueCatService.cachedEntitlementSnapshot
        legacyAppPurchaseSnapshot = legacyAppPurchaseTracker.cachedLegacyAppPurchaseSnapshot
        hasConfigured = true
        startTrialIfMissingEntitlement()
        applyStatus(computeStatus(), source: .bootstrap)
    }

    func startTrial() async {
        startTrialIfNeeded(markOnboardingSeen: true)
        applyStatus(computeStatus(), source: .stateChange)
    }

    func finishOnboardingWithoutTrial() {
        defaults[AppDefaults.hasSeenOnboarding] = true
        applyStatus(computeStatus(), source: .stateChange)
    }

    func refresh() async {
        configureIfNeeded()

        legacyAppPurchaseSnapshot = await legacyAppPurchaseTracker.refreshLegacyAppPurchaseSnapshot()

        do {
            revenueCatEntitlementSnapshot = try await revenueCatService.fetchEntitlementSnapshot()
            lastError = nil
        } catch {
            let purchaseError = ProPurchaseError(error: error)
            AppLogger.purchase.error("Failed to refresh customer info: \(purchaseError.localizedDescription)")
            lastError = purchaseError
        }

        applyStatus(computeStatus(), source: .refresh)
    }

    func loadOfferings() async {
        configureIfNeeded()

        if currentOffering != nil {
            availablePlans = Self.resolveAvailablePlans(offering: currentOffering, offeringsError: nil)
            return
        }

        var offeringsError: Error?
        do {
            currentOffering = try await revenueCatService.fetchCurrentOffering()
        } catch {
            AppLogger.purchase.error("Failed to load offerings: \(error.localizedDescription)")
            currentOffering = nil
            offeringsError = error
        }

        availablePlans = Self.resolveAvailablePlans(offering: currentOffering, offeringsError: offeringsError)
    }

    func purchase(_ plan: ProPlan) async throws {
        configureIfNeeded()
        clearPaywallMessages()
        purchaseInProgressPlan = plan
        defer { purchaseInProgressPlan = nil }

        do {
            let snapshot = try await revenueCatService.purchase(plan: plan)
            lastError = nil
            revenueCatEntitlementSnapshot = snapshot
            applyStatus(computeStatus(), source: .stateChange)
            if !status.isPro {
                let didUnlock = await refreshEntitlementStateAfterTransaction()
                if !didUnlock {
                    throw ProPurchaseError.activationPending
                }
            }
            if status.isPro {
                defaults[AppDefaults.hasSeenOnboarding] = true
            }
            paywallSuccessMessage = String(localized: "Purchase successful. Pro unlocked.")
        } catch {
            let purchaseError = ProPurchaseError(error: error)
            lastError = purchaseError
            paywallErrorMessage = purchaseError == .purchaseCancelled ? nil : purchaseError.errorDescription
            paywallSuccessMessage = nil
            throw purchaseError
        }
    }

    func restorePurchases() async throws {
        configureIfNeeded()
        clearPaywallMessages()
        isRestoringPurchases = true
        defer { isRestoringPurchases = false }

        do {
            let snapshot = try await revenueCatService.restorePurchases()
            lastError = nil
            revenueCatEntitlementSnapshot = snapshot
            applyStatus(computeStatus(), source: .stateChange)
            if !status.isPro {
                if snapshot != nil {
                    let didUnlock = await refreshEntitlementStateAfterTransaction()
                    if !didUnlock {
                        throw ProPurchaseError.activationPending
                    }
                } else {
                    paywallErrorMessage = String(localized: "No active purchase found on this account.")
                }
            }
            if status.isPro {
                paywallSuccessMessage = String(localized: "Purchase restored.")
            }
        } catch {
            let purchaseError = ProPurchaseError(error: error)
            lastError = purchaseError
            paywallErrorMessage = purchaseError == .purchaseCancelled ? nil : purchaseError.errorDescription
            paywallSuccessMessage = nil
            throw purchaseError
        }
    }

    func planProduct(for plan: ProPlan) -> ProPlanProduct {
        availablePlans.first(where: { $0.plan == plan }) ?? .fallback(for: plan)
    }

    func markExpiredPromptHandled() {
        shouldOpenProSettings = false
    }

    static func makeAvailablePlans(packageMetadata: [ProPlan: ProPlanPackageMetadata]?, offeringsAttempted: Bool = false) -> [ProPlanProduct] {
        [ProPlan.yearly, .lifetime].map { plan in
            let fallback = ProPlanProduct.fallback(for: plan, isAvailable: packageMetadata == nil && !offeringsAttempted)

            guard let metadata = packageMetadata?[plan] else {
                return fallback
            }

            return .init(
                plan: plan,
                title: fallback.title,
                displayPrice: metadata.displayPrice,
                billingDetail: metadata.billingDetail,
                subtitle: fallback.subtitle,
                badge: fallback.badge,
                isAvailable: metadata.isAvailable
            )
        }
    }

    private func clearPaywallMessages() {
        paywallErrorMessage = nil
        paywallSuccessMessage = nil
    }

    private func startTrialIfMissingEntitlement() {
        guard Self.resolvedEntitlementSnapshot(
            revenueCatSnapshot: revenueCatEntitlementSnapshot,
            legacySnapshot: legacyAppPurchaseSnapshot
        ) == nil else {
            return
        }

        startTrialIfNeeded(markOnboardingSeen: false)
    }

    private func startTrialIfNeeded(markOnboardingSeen: Bool) {
        if markOnboardingSeen {
            defaults[AppDefaults.hasSeenOnboarding] = true
        }

        if defaults[AppDefaults.trialStartDate] == nil {
            let resolvedStartDate = now()
            defaults[AppDefaults.trialStartDate] = resolvedStartDate
            AppLogger.purchase.notice("Started local trial at \(resolvedStartDate.formatted())")
        }
    }

    private func refreshEntitlementStateAfterTransaction() async -> Bool {
        for attempt in 1...Constants.transactionRefreshAttempts {
            do {
                let snapshot = try await revenueCatService.fetchEntitlementSnapshot()
                revenueCatEntitlementSnapshot = snapshot
                applyStatus(computeStatus(), source: .stateChange)

                if status.isPro {
                    AppLogger.purchase.notice("Entitlement refresh succeeded after transaction on attempt \(attempt).")
                    return true
                }
            } catch {
                AppLogger.purchase.error("Failed to refresh entitlement after transaction on attempt \(attempt): \(error.localizedDescription)")
            }

            if attempt < Constants.transactionRefreshAttempts {
                try? await Task.sleep(nanoseconds: Constants.transactionRefreshDelayNanoseconds)
            }
        }

        AppLogger.purchase.error("Entitlement remained inactive after transaction refresh attempts.")
        return false
    }

    private func applyEntitlementSnapshot(_ snapshot: ProEntitlementSnapshot?, source: StatusUpdateSource) {
        revenueCatEntitlementSnapshot = snapshot
        applyStatus(computeStatus(), source: source)
    }

    private func applyStatus(_ newStatus: ProStatus, source: StatusUpdateSource) {
        let previousStatus = status
        status = newStatus

        if shouldPromptForExpiredTransition(from: previousStatus, to: newStatus, source: source) {
            shouldOpenProSettings = true
            hasPromptedForExpiredStateThisSession = true
        }

        if source == .refresh {
            hasCompletedInitialRefresh = true
        }
    }

    private func shouldPromptForExpiredTransition(
        from previousStatus: ProStatus,
        to newStatus: ProStatus,
        source: StatusUpdateSource
    ) -> Bool {
        guard newStatus == .expired, !hasPromptedForExpiredStateThisSession else {
            return false
        }
        guard Self.accessEntitlementState(status: newStatus, lastError: lastError) != .trial else {
            return false
        }
        guard !isFirstLaunch else {
            return false
        }

        switch source {
        case .bootstrap:
            return false
        case .refresh:
            return !hasCompletedInitialRefresh || previousStatus != .expired
        case .stateChange:
            return previousStatus != .expired
        }
    }

    private func computeStatus() -> ProStatus {
        Self.computeStatus(
            entitlementSnapshot: Self.resolvedEntitlementSnapshot(
                revenueCatSnapshot: revenueCatEntitlementSnapshot,
                legacySnapshot: legacyAppPurchaseSnapshot
            ),
            defaults: defaults,
            now: now
        )
    }

    private static func resolvedEntitlementSnapshot(
        revenueCatSnapshot: ProEntitlementSnapshot?,
        legacySnapshot: LegacyAppPurchaseSnapshot?
    ) -> ProEntitlementSnapshot? {
        revenueCatSnapshot ?? legacySnapshot?.asEntitlementSnapshot
    }

    private static func computeStatus(
        entitlementSnapshot: ProEntitlementSnapshot?,
        defaults: UserDefaults,
        now: () -> Date
    ) -> ProStatus {
        if let entitlementSnapshot {
            return .pro(
                plan: entitlementSnapshot.plan,
                expirationDate: entitlementSnapshot.expirationDate,
                willRenew: entitlementSnapshot.willRenew
            )
        }

        guard let trialStart = defaults[AppDefaults.trialStartDate] else {
            return .expired
        }
        let expiresAt = trialStart.addingTimeInterval(Constants.trialDuration)
        let remaining = expiresAt.timeIntervalSince(now())

        if remaining > 0 {
            let daysRemaining = max(1, Int(ceil(remaining / 86_400)))
            return .trial(daysRemaining: daysRemaining, expiresAt: expiresAt)
        }

        return .expired
    }

    private static func packageMetadata(from offering: ProOfferingSnapshot?) -> [ProPlan: ProPlanPackageMetadata]? {
        guard let offering else {
            return nil
        }

        return offering.isEmpty ? nil : offering.packageMetadata
    }

    private static func resolveAvailablePlans(offering: ProOfferingSnapshot?, offeringsError: Error?) -> [ProPlanProduct] {
        let purchaseError = offeringsError.map(ProPurchaseError.init(error:))
        let shouldKeepFallbackAvailable = purchaseError == .network

        return makeAvailablePlans(
            packageMetadata: packageMetadata(from: offering),
            offeringsAttempted: !shouldKeepFallbackAvailable
        )
    }

    private static func accessEntitlementState(
        status: ProStatus,
        lastError: ProPurchaseError?
    ) -> AccessEntitlementState {
        if status == .expired, lastError == .network {
            return .trial
        }

        switch status {
        case .trial:
            return .trial
        case .expired:
            return .expired
        case .pro:
            return .pro
        }
    }

}
