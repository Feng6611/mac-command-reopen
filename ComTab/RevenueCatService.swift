//
//  RevenueCatService.swift
//  ComTab
//
//  Created by Codex on 2026/3/28.
//

import Foundation
import RevenueCat
import os

enum RevenueCatConfiguration {
    static let apiKey = "test_JMcWXYqTETEunXPsXqWRBtbffYU"
    static let entitlementIdentifier = "command_reopen_pro"
    static let offeringIdentifier = "default"
    static let yearlyProductIdentifier = "com.dev.kkuk.CommandReopen.yearly"
    static let lifetimeProductIdentifier = "com.dev.kkuk.CommandReopen.lifetime"
}

private enum RevenueCatSnapshotParser {
    nonisolated static func makeEntitlementSnapshot(from customerInfo: CustomerInfo?) -> ProEntitlementSnapshot? {
        let entitlementIdentifier = "command_reopen_pro"
        let yearlyProductIdentifier = "com.dev.kkuk.CommandReopen.yearly"
        let lifetimeProductIdentifier = "com.dev.kkuk.CommandReopen.lifetime"

        guard
            let customerInfo,
            let entitlement = customerInfo.entitlements.all[entitlementIdentifier],
            entitlement.isActive
        else {
            return nil
        }

        let plan: ProPlan
        switch entitlement.productIdentifier {
        case lifetimeProductIdentifier:
            plan = .lifetime
        case yearlyProductIdentifier:
            plan = .yearly
        default:
            plan = entitlement.expirationDate == nil ? .lifetime : .yearly
        }

        return ProEntitlementSnapshot(plan: plan, expirationDate: entitlement.expirationDate)
    }
}

extension ProPlan {
    var productIdentifier: String {
        switch self {
        case .yearly:
            RevenueCatConfiguration.yearlyProductIdentifier
        case .lifetime:
            RevenueCatConfiguration.lifetimeProductIdentifier
        }
    }
}

struct ProEntitlementSnapshot: Equatable {
    let plan: ProPlan
    let expirationDate: Date?
}

@MainActor
protocol RevenueCatServicing: AnyObject {
    var cachedEntitlementSnapshot: ProEntitlementSnapshot? { get }
    var customerInfoDidChange: ((ProEntitlementSnapshot?) -> Void)? { get set }

    func configureIfNeeded()
    func fetchCurrentOffering() async throws -> Offering?
    func fetchEntitlementSnapshot() async throws -> ProEntitlementSnapshot?
    func purchase(plan: ProPlan, offering: Offering?) async throws -> ProEntitlementSnapshot?
    func restorePurchases() async throws -> ProEntitlementSnapshot?
}

@MainActor
final class RevenueCatService: NSObject, RevenueCatServicing {
    static let shared = RevenueCatService()

    var customerInfoDidChange: ((ProEntitlementSnapshot?) -> Void)?

    private(set) var isConfigured = false

    var cachedEntitlementSnapshot: ProEntitlementSnapshot? {
        guard isConfigured else {
            return nil
        }

        return RevenueCatSnapshotParser.makeEntitlementSnapshot(from: Purchases.shared.cachedCustomerInfo)
    }

    func configureIfNeeded() {
        guard !isConfigured else {
            return
        }

#if DEBUG
        Purchases.logLevel = .debug
#else
        Purchases.logLevel = .warn
#endif

        let configuration = Configuration
            .builder(withAPIKey: RevenueCatConfiguration.apiKey)
            .with(storeKitVersion: .storeKit2)
            .with(entitlementVerificationMode: .informational)
            .with(showStoreMessagesAutomatically: true)
            .build()

        Purchases.configure(with: configuration)
        Purchases.shared.delegate = self
        isConfigured = true

        AppLogger.purchase.notice("RevenueCat configured.")
    }

    func fetchCurrentOffering() async throws -> Offering? {
        try ensureConfigured()

        let offerings = try await Purchases.shared.offerings()
        return offerings.current ?? offerings.all[RevenueCatConfiguration.offeringIdentifier]
    }

    func fetchEntitlementSnapshot() async throws -> ProEntitlementSnapshot? {
        try ensureConfigured()

        let customerInfo = try await Purchases.shared.customerInfo()
        return RevenueCatSnapshotParser.makeEntitlementSnapshot(from: customerInfo)
    }

    func purchase(plan: ProPlan, offering: Offering?) async throws -> ProEntitlementSnapshot? {
        try ensureConfigured()

        let resolvedOffering = try await resolveOffering(offering)
        guard let package = package(for: plan, in: resolvedOffering) else {
            throw ProPurchaseError.packageNotFound(plan)
        }

        let result = try await Purchases.shared.purchase(package: package)
        if result.userCancelled {
            throw ProPurchaseError.purchaseCancelled
        }

        return RevenueCatSnapshotParser.makeEntitlementSnapshot(from: result.customerInfo)
    }

    func restorePurchases() async throws -> ProEntitlementSnapshot? {
        try ensureConfigured()

        let customerInfo = try await Purchases.shared.restorePurchases()
        return RevenueCatSnapshotParser.makeEntitlementSnapshot(from: customerInfo)
    }

    private func ensureConfigured() throws {
        guard isConfigured else {
            throw ProPurchaseError.notConfigured
        }
    }

    private func resolveOffering(_ offering: Offering?) async throws -> Offering {
        if let offering {
            return offering
        }

        if let fetched = try await fetchCurrentOffering() {
            return fetched
        }

        throw ProPurchaseError.offeringUnavailable
    }

    private func package(for plan: ProPlan, in offering: Offering) -> Package? {
        switch plan {
        case .yearly:
            return offering.annual
                ?? offering.availablePackages.first(where: { $0.storeProduct.productIdentifier == plan.productIdentifier })
        case .lifetime:
            return offering.lifetime
                ?? offering.availablePackages.first(where: { $0.storeProduct.productIdentifier == plan.productIdentifier })
        }
    }
}

extension RevenueCatService: PurchasesDelegate {
    nonisolated func purchases(_ purchases: Purchases, receivedUpdated customerInfo: CustomerInfo) {
        let snapshot = RevenueCatSnapshotParser.makeEntitlementSnapshot(from: customerInfo)

        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            self.customerInfoDidChange?(snapshot)
        }
    }
}
