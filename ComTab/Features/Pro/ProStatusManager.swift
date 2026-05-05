//
//  ProStatusManager.swift
//  ComTab
//
//  Created by CHEN on 2026/3/28.
//

import Combine
import Defaults
import Foundation
import RevenueCatCommerceKit
import os

@MainActor
final class ProStatusManager: ObservableObject {
    enum Constants {
        static let trialDuration: TimeInterval = 2 * 24 * 60 * 60
        static let transactionRefreshAttempts = 3
        static let transactionRefreshDelayNanoseconds: UInt64 = 750_000_000
    }

    private enum StatusUpdateSource {
        case bootstrap
        case refresh
        case stateChange
    }

    static let shared = ProStatusManager()

    @Published private(set) var status: ProStatus
    @Published private(set) var currentOffering: CommerceOffering?
    @Published private(set) var availablePlans: [ProPlanProduct]
    @Published private(set) var lastError: ProPurchaseError?
    @Published private(set) var purchaseInProgressPlan: CommercePlan?
    @Published private(set) var isRestoringPurchases = false

    var currentEntitlementSnapshot: CommerceEntitlement? { entitlementSnapshot }
    @Published private(set) var paywallErrorMessage: String?
    @Published private(set) var paywallSuccessMessage: String?
    @Published private(set) var shouldOpenProSettings = false

    private let defaults: UserDefaults
    private let commerceClient: any CommerceClient
    private let now: () -> Date

    private var entitlementSnapshot: CommerceEntitlement?
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
        commerceClient: (any CommerceClient)? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        let client = commerceClient ?? RevenueCatCommerceClient(
            configuration: RevenueCatConfiguration.commerceConfiguration
        )
        let cachedSnapshot = client.cachedEntitlement
        if cachedSnapshot == nil,
           defaults[AppDefaults.trialStartDate] == nil {
            let resolvedStartDate = now()
            defaults[AppDefaults.trialStartDate] = resolvedStartDate
            AppLogger.purchase.notice("Started local trial at \(resolvedStartDate.formatted())")
        }
        self.defaults = defaults
        self.commerceClient = client
        self.now = now
        self.entitlementSnapshot = cachedSnapshot
        self.currentOffering = nil
        self.availablePlans = ProPlanProduct.fallbackPlans
        self.lastError = nil
        self.purchaseInProgressPlan = nil
        self.paywallErrorMessage = nil
        self.paywallSuccessMessage = nil
        self.status = Self.computeStatus(entitlementSnapshot: cachedSnapshot, defaults: defaults, now: now)
    }

    func configureIfNeeded() {
        guard !hasConfigured else {
            return
        }

        commerceClient.entitlementDidChange = { [weak self] snapshot in
            self?.applyEntitlementSnapshot(snapshot, source: .stateChange)
        }
        commerceClient.configureIfNeeded()
        entitlementSnapshot = commerceClient.cachedEntitlement
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

        do {
            entitlementSnapshot = try await commerceClient.refreshEntitlement()
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
            currentOffering = try await commerceClient.loadOffering()
        } catch {
            AppLogger.purchase.error("Failed to load offerings: \(error.localizedDescription)")
            currentOffering = nil
            offeringsError = error
        }

        availablePlans = Self.resolveAvailablePlans(offering: currentOffering, offeringsError: offeringsError)
    }

    func purchase(_ plan: CommercePlan) async throws {
        configureIfNeeded()
        clearPaywallMessages()
        purchaseInProgressPlan = plan
        defer { purchaseInProgressPlan = nil }

        do {
            let snapshot = try await commerceClient.purchase(plan)
            lastError = nil
            entitlementSnapshot = snapshot
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
            let snapshot = try await commerceClient.restorePurchases()
            lastError = nil
            entitlementSnapshot = snapshot
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

    func planProduct(for plan: CommercePlan) -> ProPlanProduct {
        availablePlans.first(where: { $0.plan == plan }) ?? .fallback(for: plan)
    }

    func markExpiredPromptHandled() {
        shouldOpenProSettings = false
    }

    static func makeAvailablePlans(packageMetadata: [CommercePlan: ProPlanPackageMetadata]?, offeringsAttempted: Bool = false) -> [ProPlanProduct] {
        [CommercePlan.yearly, .lifetime].map { plan in
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
        guard entitlementSnapshot == nil else {
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
                let snapshot = try await commerceClient.refreshEntitlement()
                entitlementSnapshot = snapshot
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

    private func applyEntitlementSnapshot(_ snapshot: CommerceEntitlement?, source: StatusUpdateSource) {
        entitlementSnapshot = snapshot
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
            entitlementSnapshot: entitlementSnapshot,
            defaults: defaults,
            now: now
        )
    }

    private static func computeStatus(
        entitlementSnapshot: CommerceEntitlement?,
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

    private static func packageMetadata(from offering: CommerceOffering?) -> [CommercePlan: ProPlanPackageMetadata]? {
        guard let offering else {
            return nil
        }

        guard !offering.isEmpty else {
            return nil
        }

        return Dictionary(uniqueKeysWithValues: offering.products.map { product in
            (
                product.plan,
                ProPlanPackageMetadata(
                    displayPrice: product.displayPrice,
                    billingDetail: product.plan == .yearly ? String(localized: "per year") : String(localized: "once"),
                    isAvailable: product.isAvailable
                )
            )
        })
    }

    private static func resolveAvailablePlans(offering: CommerceOffering?, offeringsError: Error?) -> [ProPlanProduct] {
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
