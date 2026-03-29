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
    nonisolated static let apiKeyInfoKey = "ComTabRevenueCatAPIKey"
    nonisolated static let bundledAPIKeyFallback = "appl_dDJatXaPwFuBLAelZfwDtGTNDbs"
    nonisolated static var apiKey: String {
        let configuredKey = (Bundle.main.object(forInfoDictionaryKey: apiKeyInfoKey) as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let configuredKey, !configuredKey.isEmpty {
            return configuredKey
        }

        return bundledAPIKeyFallback
    }
    nonisolated static let entitlementIdentifier = "command reopen Pro"
    nonisolated static let offeringIdentifier = "default"
    nonisolated static let yearlyProductIdentifier = "com.dev.kkuk.CommandReopen.yearly"
    nonisolated static let lifetimeProductIdentifier = "com.dev.kkuk.CommandReopen.lifetime"
}

private enum RevenueCatSnapshotParser {
    nonisolated static func resolveActiveEntitlement(from customerInfo: CustomerInfo, logger: Logger) -> EntitlementInfo? {
        if let configuredEntitlement = customerInfo.entitlements.all[RevenueCatConfiguration.entitlementIdentifier] {
            return configuredEntitlement
        }

        let fallbackEntitlement = customerInfo.entitlements.all.values.first { entitlement in
            entitlement.isActive && (
                entitlement.productIdentifier == RevenueCatConfiguration.yearlyProductIdentifier
                    || entitlement.productIdentifier == RevenueCatConfiguration.lifetimeProductIdentifier
            )
        }

        if let fallbackEntitlement {
            logger.notice(
                "Falling back to active entitlement product=\(fallbackEntitlement.productIdentifier) because configured entitlement id=\(RevenueCatConfiguration.entitlementIdentifier) was not found."
            )
        }

        return fallbackEntitlement
    }

    nonisolated static func makeEntitlementSnapshot(from customerInfo: CustomerInfo?) -> ProEntitlementSnapshot? {
        let logger = Logger(
            subsystem: Bundle.main.bundleIdentifier ?? "com.dev.kkuk.CmdReopen",
            category: "Purchase"
        )

        guard let customerInfo else {
            return nil
        }

        guard let entitlement = resolveActiveEntitlement(from: customerInfo, logger: logger) else {
            let activeEntitlementIdentifiers = customerInfo.entitlements.all
                .filter { $0.value.isActive }
                .map(\.key)
                .sorted()
                .joined(separator: ", ")
            let activeSubscriptionIdentifiers = Array(customerInfo.activeSubscriptions)
                .sorted()
                .joined(separator: ", ")

            if !activeEntitlementIdentifiers.isEmpty || !activeSubscriptionIdentifiers.isEmpty {
                logger.error(
                    "Expected entitlement id=\(RevenueCatConfiguration.entitlementIdentifier) not found. activeEntitlements=[\(activeEntitlementIdentifiers)] activeSubscriptions=[\(activeSubscriptionIdentifiers)]"
                )
            }
            return nil
        }

        guard entitlement.isActive else {
            logger.debug(
                "Entitlement id=\(RevenueCatConfiguration.entitlementIdentifier) present but inactive. product=\(entitlement.productIdentifier)"
            )
            return nil
        }

        let plan: ProPlan
        switch entitlement.productIdentifier {
        case RevenueCatConfiguration.lifetimeProductIdentifier:
            plan = .lifetime
        case RevenueCatConfiguration.yearlyProductIdentifier:
            plan = .yearly
        default:
            plan = entitlement.expirationDate == nil ? .lifetime : .yearly
        }

        logger.notice(
            "Mapped active entitlement id=\(RevenueCatConfiguration.entitlementIdentifier) product=\(entitlement.productIdentifier) plan=\(plan.rawValue)"
        )

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

struct ProEntitlementSnapshot: Equatable, Sendable {
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

        guard !RevenueCatConfiguration.apiKey.isEmpty else {
            AppLogger.purchase.error("RevenueCat configuration skipped because \(RevenueCatConfiguration.apiKeyInfoKey) is missing.")
            return
        }

#if !DEBUG
        guard !RevenueCatConfiguration.apiKey.hasPrefix("test_") else {
            AppLogger.purchase.error("Skipping RevenueCat configuration in non-debug build because the API key is a test key.")
            return
        }
#endif

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
        let resolvedOffering = offerings.current ?? offerings.all[RevenueCatConfiguration.offeringIdentifier]

        if let resolvedOffering {
            let packageIdentifiers = resolvedOffering.availablePackages.map(\.identifier).joined(separator: ", ")
            AppLogger.purchase.notice(
                "Loaded RevenueCat offering id=\(resolvedOffering.identifier) packages=[\(packageIdentifiers)]"
            )
        } else {
            AppLogger.purchase.error(
                "RevenueCat returned no current/default offering. current=\(String(describing: offerings.current?.identifier))"
            )
        }

        return resolvedOffering
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
