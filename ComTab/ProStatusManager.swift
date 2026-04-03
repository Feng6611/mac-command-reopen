//
//  ProStatusManager.swift
//  ComTab
//
//  Created by CHEN on 2026/3/28.
//

import Combine
import Foundation
import RevenueCat
import os

enum ProPlan: String, Equatable, Sendable {
    case yearly
    case lifetime
}

struct ProPlanPackageMetadata: Equatable {
    let displayPrice: String
    let billingDetail: String
    let isAvailable: Bool
}

struct ProPlanProduct: Equatable, Identifiable {
    let plan: ProPlan
    let title: String
    let displayPrice: String
    let billingDetail: String
    let subtitle: String
    let badge: String?
    let isAvailable: Bool

    var id: ProPlan { plan }

    static func fallback(for plan: ProPlan, isAvailable: Bool = true) -> Self {
        switch plan {
        case .yearly:
            return .init(
                plan: .yearly,
                title: String(localized: "Yearly"),
                displayPrice: "$5.99",
                billingDetail: String(localized: "per year"),
                subtitle: String(localized: "Auto-renews annually"),
                badge: nil,
                isAvailable: isAvailable
            )
        case .lifetime:
            return .init(
                plan: .lifetime,
                title: String(localized: "Lifetime"),
                displayPrice: "$10.99",
                billingDetail: String(localized: "once"),
                subtitle: String(localized: "Pay once, use forever"),
                badge: String(localized: "Best Value"),
                isAvailable: isAvailable
            )
        }
    }

    static let fallbackPlans: [Self] = [
        .fallback(for: .yearly),
        .fallback(for: .lifetime)
    ]
}

enum ProPurchaseError: Error, Equatable {
    case notConfigured
    case offeringUnavailable
    case packageNotFound(ProPlan)
    case purchaseCancelled
    case purchaseNotAllowed
    case activationPending
    case invalidReceipt
    case network
    case invalidCredentials
    case productUnavailable
    case unknown(String)

    init(error: Error) {
        if let purchaseError = error as? ProPurchaseError {
            self = purchaseError
            return
        }

        let nsError = error as NSError
        if nsError.domain == RevenueCat.ErrorCode.errorDomain,
           let errorCode = RevenueCat.ErrorCode(rawValue: nsError.code) {
            switch errorCode {
            case .purchaseCancelledError:
                self = .purchaseCancelled
            case .purchaseNotAllowedError:
                self = .purchaseNotAllowed
            case .invalidReceiptError:
                self = .invalidReceipt
            case .productNotAvailableForPurchaseError:
                self = .productUnavailable
            case .networkError:
                self = .network
            case .invalidCredentialsError:
                self = .invalidCredentials
            case .configurationError:
                self = .notConfigured
            default:
                self = .unknown(nsError.localizedDescription)
            }
        } else {
            self = .unknown(nsError.localizedDescription)
        }
    }
}

extension ProPurchaseError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .notConfigured:
            "Purchases are not configured yet."
        case .offeringUnavailable:
            "No products are currently available."
        case .packageNotFound(let plan):
            "The \(plan.rawValue) product is not available in the current offering."
        case .purchaseCancelled:
            "The purchase was cancelled."
        case .purchaseNotAllowed:
            "Purchases are not allowed on this Mac."
        case .activationPending:
            "Purchase completed, but Pro access is still syncing. Please wait a moment or use Restore Purchase."
        case .invalidReceipt:
            "The App Store did not finish syncing this purchase yet. Please try again in a moment or use Restore Purchase."
        case .network:
            "A network connection is required to load purchases."
        case .invalidCredentials:
            "The RevenueCat API key is invalid."
        case .productUnavailable:
            "This product is not available for purchase."
        case .unknown(let message):
            message
        }
    }
}

enum ProStatus: Equatable {
    case trial(daysRemaining: Int, expiresAt: Date)
    case expired
    case pro(plan: ProPlan, expirationDate: Date?, willRenew: Bool)

    var isActive: Bool {
        switch self {
        case .trial, .pro:
            true
        case .expired:
            false
        }
    }

    var isPro: Bool {
        if case .pro = self {
            return true
        }

        return false
    }

    var isTrial: Bool {
        if case .trial = self {
            return true
        }

        return false
    }

    var renewalState: ProRenewalState? {
        renewalState(now: Date())
    }

    func renewalState(now: Date) -> ProRenewalState? {
        guard case .pro(let plan, let expirationDate, let willRenew) = self,
              plan == .yearly,
              let expirationDate else {
            return nil
        }

        let remaining = expirationDate.timeIntervalSince(now)
        let daysRemaining = remaining > 0 ? max(1, Int(ceil(remaining / 86_400))) : 0

        if willRenew {
            return .renews(on: expirationDate, daysRemaining: daysRemaining)
        }

        return .ends(on: expirationDate, daysRemaining: daysRemaining)
    }
}

enum ProRenewalState: Equatable {
    case renews(on: Date, daysRemaining: Int)
    case ends(on: Date, daysRemaining: Int)
}

@MainActor
final class ProStatusManager: ObservableObject {
    private enum Constants {
        static let trialStartDateKey = "com.comtab.trialStartDate"
        static let hasSeenOnboardingKey = "com.comtab.hasSeenOnboarding"
        static let trialDuration: TimeInterval = 7 * 24 * 60 * 60
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
    @Published private(set) var currentOffering: Offering?
    @Published private(set) var availablePlans: [ProPlanProduct]
    @Published private(set) var lastError: ProPurchaseError?
    @Published private(set) var purchaseInProgressPlan: ProPlan?
    @Published private(set) var isRestoringPurchases = false

    var currentEntitlementSnapshot: ProEntitlementSnapshot? {
        entitlementSnapshot
    }
    @Published private(set) var paywallErrorMessage: String?
    @Published private(set) var paywallSuccessMessage: String?
    @Published private(set) var shouldOpenProSettings = false

    private let defaults: UserDefaults
    private let revenueCatService: any RevenueCatServicing
    private let now: () -> Date

    private var entitlementSnapshot: ProEntitlementSnapshot?
    private var hasConfigured = false
    private var hasCompletedInitialRefresh = false
    private var hasPromptedForExpiredStateThisSession = false

    var isFirstLaunch: Bool {
        !defaults.bool(forKey: Constants.hasSeenOnboardingKey)
    }

    var accessEntitlementState: AccessEntitlementState {
        Self.accessEntitlementState(status: status, lastError: lastError)
    }

    init(
        defaults: UserDefaults = .standard,
        revenueCatService: (any RevenueCatServicing)? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        let service = revenueCatService ?? RevenueCatService.shared
        let cachedSnapshot = service.cachedEntitlementSnapshot
        self.defaults = defaults
        self.revenueCatService = service
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

        revenueCatService.customerInfoDidChange = { [weak self] snapshot in
            self?.applyEntitlementSnapshot(snapshot, source: .stateChange)
        }
        revenueCatService.configureIfNeeded()
        entitlementSnapshot = revenueCatService.cachedEntitlementSnapshot
        hasConfigured = true
        applyStatus(computeStatus(), source: .bootstrap)
    }

    func startTrial() async {
        defaults.set(true, forKey: Constants.hasSeenOnboardingKey)

        if defaults.object(forKey: Constants.trialStartDateKey) == nil {
            let resolvedStartDate = now()
            defaults.set(resolvedStartDate, forKey: Constants.trialStartDateKey)
            AppLogger.purchase.notice("Started local trial at \(resolvedStartDate.formatted())")
        }

        applyStatus(computeStatus(), source: .stateChange)
    }

    func markOnboardingSeen() {
        defaults.set(true, forKey: Constants.hasSeenOnboardingKey)
    }

    func refresh() async {
        configureIfNeeded()

        var offeringsError: Error?
        do {
            currentOffering = try await revenueCatService.fetchCurrentOffering()
        } catch {
            AppLogger.purchase.error("Failed to load offerings: \(error.localizedDescription)")
            currentOffering = nil
            offeringsError = error
        }
        availablePlans = Self.resolveAvailablePlans(offering: currentOffering, offeringsError: offeringsError)

        do {
            entitlementSnapshot = try await revenueCatService.fetchEntitlementSnapshot()
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
            let snapshot = try await revenueCatService.purchase(plan: plan, offering: currentOffering)
            lastError = nil
            entitlementSnapshot = snapshot
            applyStatus(computeStatus(), source: .stateChange)
            if !status.isPro {
                let didUnlock = await refreshEntitlementStateAfterTransaction()
                if !didUnlock {
                    throw ProPurchaseError.activationPending
                }
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

    private func refreshEntitlementStateAfterTransaction() async -> Bool {
        for attempt in 1...Constants.transactionRefreshAttempts {
            do {
                let snapshot = try await revenueCatService.fetchEntitlementSnapshot()
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

    private func applyEntitlementSnapshot(_ snapshot: ProEntitlementSnapshot?, source: StatusUpdateSource) {
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
        Self.computeStatus(entitlementSnapshot: entitlementSnapshot, defaults: defaults, now: now)
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

        guard let trialStart = defaults.object(forKey: Constants.trialStartDateKey) as? Date else {
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

    private static func packageMetadata(from offering: Offering?) -> [ProPlan: ProPlanPackageMetadata]? {
        guard let offering else {
            return nil
        }

        var metadata: [ProPlan: ProPlanPackageMetadata] = [:]

        for plan in [ProPlan.yearly, .lifetime] {
            guard let package = offering.package(for: plan) else {
                continue
            }

            metadata[plan] = .init(
                displayPrice: package.storeProduct.localizedPriceString,
                billingDetail: plan == .yearly ? String(localized: "per year") : String(localized: "once"),
                isAvailable: true
            )
        }

        return metadata.isEmpty ? nil : metadata
    }

    private static func resolveAvailablePlans(offering: Offering?, offeringsError: Error?) -> [ProPlanProduct] {
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
