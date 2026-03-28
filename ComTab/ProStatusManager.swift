//
//  ProStatusManager.swift
//  ComTab
//
//  Created by CHEN on 2026/3/28.
//

import Combine
import Foundation
import RevenueCat
import StoreKit
import os

enum ProPlan: String, Equatable {
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
                title: "Yearly",
                displayPrice: "$5.99",
                billingDetail: "per year",
                subtitle: "Auto-renews annually",
                badge: nil,
                isAvailable: isAvailable
            )
        case .lifetime:
            return .init(
                plan: .lifetime,
                title: "Lifetime",
                displayPrice: "$10.99",
                billingDetail: "once",
                subtitle: "Pay once, use forever",
                badge: "Best Value",
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
    case unsupportedDistribution
    case offeringUnavailable
    case packageNotFound(ProPlan)
    case purchaseCancelled
    case purchaseNotAllowed
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
        if let errorCode = RevenueCat.ErrorCode(rawValue: nsError.code) {
            switch errorCode {
            case .purchaseCancelledError:
                self = .purchaseCancelled
            case .purchaseNotAllowedError:
                self = .purchaseNotAllowed
            case .productNotAvailableForPurchaseError:
                self = .productUnavailable
            case .networkError:
                self = .network
            case .invalidCredentialsError:
                self = .invalidCredentials
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
        case .unsupportedDistribution:
            "Purchases are only available in the Mac App Store version."
        case .offeringUnavailable:
            "No products are currently available."
        case .packageNotFound(let plan):
            "The \(plan.rawValue) product is not available in the current offering."
        case .purchaseCancelled:
            "The purchase was cancelled."
        case .purchaseNotAllowed:
            "Purchases are not allowed on this Mac."
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
    case pro(plan: ProPlan, expirationDate: Date?)

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
}

@MainActor
final class ProStatusManager: ObservableObject {
    private enum Constants {
        static let trialStartDateKey = "com.comtab.trialStartDate"
        static let hasSeenOnboardingKey = "com.comtab.hasSeenOnboarding"
        static let trialDuration: TimeInterval = 7 * 24 * 60 * 60
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
    @Published private(set) var paywallErrorMessage: String?
    @Published private(set) var shouldOpenProSettings = false

    private let defaults: UserDefaults
    private let revenueCatService: any RevenueCatServicing
    private let now: () -> Date
    private let trialStartDateProvider: () async -> Date?

    private var entitlementSnapshot: ProEntitlementSnapshot?
    private var hasConfigured = false
    private var hasCompletedInitialRefresh = false
    private var hasPromptedForExpiredStateThisSession = false

    var isFirstLaunch: Bool {
        !defaults.bool(forKey: Constants.hasSeenOnboardingKey)
    }

    init(
        defaults: UserDefaults = .standard,
        revenueCatService: (any RevenueCatServicing)? = nil,
        now: @escaping () -> Date = Date.init,
        trialStartDateProvider: (() async -> Date?)? = nil
    ) {
        self.defaults = defaults
        self.revenueCatService = revenueCatService ?? RevenueCatService.shared
        self.now = now
        self.trialStartDateProvider = trialStartDateProvider ?? Self.resolveTrialStartDate
        self.entitlementSnapshot = self.revenueCatService.cachedEntitlementSnapshot
        self.currentOffering = nil
        self.availablePlans = ProPlanProduct.fallbackPlans
        self.lastError = nil
        self.purchaseInProgressPlan = nil
        self.paywallErrorMessage = nil

        if DistributionChannel.current == .direct {
            self.status = .pro(plan: .lifetime, expirationDate: nil)
        } else {
            self.status = .expired
            self.status = computeStatus()
        }
    }

    func configureIfNeeded() {
        guard DistributionChannel.current == .appStore else {
            availablePlans = ProPlanProduct.fallbackPlans
            applyStatus(.pro(plan: .lifetime, expirationDate: nil), source: .bootstrap)
            return
        }

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

    func startTrial() {
        defaults.set(true, forKey: Constants.hasSeenOnboardingKey)

        if defaults.object(forKey: Constants.trialStartDateKey) == nil {
            defaults.set(now(), forKey: Constants.trialStartDateKey)
        }

        applyStatus(computeStatus(), source: .stateChange)
    }

    func refresh() async {
        guard DistributionChannel.current == .appStore else {
            currentOffering = nil
            availablePlans = ProPlanProduct.fallbackPlans
            lastError = nil
            paywallErrorMessage = nil
            applyStatus(.pro(plan: .lifetime, expirationDate: nil), source: .refresh)
            return
        }

        configureIfNeeded()
        await ensureTrialStartedIfNeeded()

        do {
            currentOffering = try await revenueCatService.fetchCurrentOffering()
        } catch {
            AppLogger.purchase.error("Failed to load offerings: \(error.localizedDescription)")
            currentOffering = nil
        }
        availablePlans = Self.makeAvailablePlans(packageMetadata: Self.packageMetadata(from: currentOffering))

        do {
            entitlementSnapshot = try await revenueCatService.fetchEntitlementSnapshot()
            lastError = nil
        } catch {
            AppLogger.purchase.error("Failed to refresh customer info: \(error.localizedDescription)")
        }

        applyStatus(computeStatus(), source: .refresh)
    }

    func loadOfferings() async {
        guard DistributionChannel.current == .appStore else {
            currentOffering = nil
            availablePlans = ProPlanProduct.fallbackPlans
            return
        }

        configureIfNeeded()

        do {
            currentOffering = try await revenueCatService.fetchCurrentOffering()
        } catch {
            AppLogger.purchase.error("Failed to load offerings: \(error.localizedDescription)")
            currentOffering = nil
        }

        availablePlans = Self.makeAvailablePlans(packageMetadata: Self.packageMetadata(from: currentOffering))
    }

    func purchase(_ plan: ProPlan) async throws {
        guard DistributionChannel.current == .appStore else {
            let error = ProPurchaseError.unsupportedDistribution
            lastError = error
            paywallErrorMessage = error.errorDescription
            throw error
        }

        configureIfNeeded()
        paywallErrorMessage = nil
        purchaseInProgressPlan = plan
        defer { purchaseInProgressPlan = nil }

        do {
            let snapshot = try await revenueCatService.purchase(plan: plan, offering: currentOffering)
            lastError = nil
            paywallErrorMessage = nil
            entitlementSnapshot = snapshot
            applyStatus(computeStatus(), source: .stateChange)
        } catch {
            let purchaseError = ProPurchaseError(error: error)
            lastError = purchaseError
            paywallErrorMessage = purchaseError == .purchaseCancelled ? nil : purchaseError.errorDescription
            throw purchaseError
        }
    }

    func restorePurchases() async throws {
        guard DistributionChannel.current == .appStore else {
            let error = ProPurchaseError.unsupportedDistribution
            lastError = error
            paywallErrorMessage = error.errorDescription
            throw error
        }

        configureIfNeeded()
        paywallErrorMessage = nil
        isRestoringPurchases = true
        defer { isRestoringPurchases = false }

        do {
            let snapshot = try await revenueCatService.restorePurchases()
            lastError = nil
            paywallErrorMessage = nil
            entitlementSnapshot = snapshot
            applyStatus(computeStatus(), source: .stateChange)
        } catch {
            let purchaseError = ProPurchaseError(error: error)
            lastError = purchaseError
            paywallErrorMessage = purchaseError == .purchaseCancelled ? nil : purchaseError.errorDescription
            throw purchaseError
        }
    }

    func planProduct(for plan: ProPlan) -> ProPlanProduct {
        availablePlans.first(where: { $0.plan == plan }) ?? .fallback(for: plan)
    }

    func markExpiredPromptHandled() {
        shouldOpenProSettings = false
    }

    static func makeAvailablePlans(packageMetadata: [ProPlan: ProPlanPackageMetadata]?) -> [ProPlanProduct] {
        [ProPlan.yearly, .lifetime].map { plan in
            let fallback = ProPlanProduct.fallback(for: plan, isAvailable: packageMetadata == nil)

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

    private func ensureTrialStartedIfNeeded() async {
        guard defaults.object(forKey: Constants.trialStartDateKey) == nil else {
            return
        }

        let resolvedStartDate = await trialStartDateProvider() ?? now()
        defaults.set(resolvedStartDate, forKey: Constants.trialStartDateKey)
        applyStatus(computeStatus(), source: .stateChange)

        AppLogger.purchase.notice("Started local trial at \(resolvedStartDate.formatted())")
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
        if DistributionChannel.current == .direct {
            return .pro(plan: .lifetime, expirationDate: nil)
        }

        if let entitlementSnapshot {
            return .pro(plan: entitlementSnapshot.plan, expirationDate: entitlementSnapshot.expirationDate)
        }

        let trialStart = defaults.object(forKey: Constants.trialStartDateKey) as? Date ?? now()
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
            guard let package = package(for: plan, in: offering) else {
                continue
            }

            metadata[plan] = .init(
                displayPrice: package.storeProduct.localizedPriceString,
                billingDetail: plan == .yearly ? "per year" : "once",
                isAvailable: true
            )
        }

        return metadata.isEmpty ? nil : metadata
    }

    private static func package(for plan: ProPlan, in offering: Offering) -> Package? {
        switch plan {
        case .yearly:
            return offering.annual
                ?? offering.availablePackages.first(where: { $0.storeProduct.productIdentifier == plan.productIdentifier })
        case .lifetime:
            return offering.lifetime
                ?? offering.availablePackages.first(where: { $0.storeProduct.productIdentifier == plan.productIdentifier })
        }
    }

    private static func resolveTrialStartDate() async -> Date? {
        guard #available(macOS 13.0, *) else {
            return nil
        }

        do {
            let verification = try await AppTransaction.shared
            switch verification {
            case .verified(let appTransaction):
                return appTransaction.originalPurchaseDate
            case .unverified(_, let error):
                AppLogger.purchase.error("AppTransaction verification failed: \(error.localizedDescription)")
                return nil
            }
        } catch {
            AppLogger.purchase.error("Unable to fetch AppTransaction: \(error.localizedDescription)")
            return nil
        }
    }
}
