//
//  RevenueCatEntitlements.swift
//  ComTab
//
//  Created by Codex on 2026/4/26.
//

import Foundation
import RevenueCat
import os

enum RevenueCatConfiguration {
    nonisolated static let apiKeyInfoKey = "ComTabRevenueCatAPIKey"
    nonisolated static var apiKey: String {
        let configuredKey = (Bundle.main.object(forInfoDictionaryKey: apiKeyInfoKey) as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let configuredKey, !configuredKey.isEmpty {
            return configuredKey
        }

        return ""
    }
    nonisolated static let entitlementIdentifier = "command reopen Pro"
    nonisolated static let offeringIdentifier = "default"
    nonisolated static let yearlyProductIdentifier = "com.dev.kkuk.CommandReopen.yearly"
    nonisolated static let lifetimeProductIdentifier = "com.dev.kkuk.CommandReopen.lifetime"
}

enum RevenueCatSnapshotParser {
    nonisolated static func resolveActiveEntitlement(from customerInfo: CustomerInfo, logger: Logger) -> EntitlementInfo? {
        let activeEntitlements = customerInfo.entitlements.all.values
            .filter(\.isActive)
            .sorted(by: Self.preferredEntitlementOrder)

        if let configuredEntitlement = customerInfo.entitlements.all[RevenueCatConfiguration.entitlementIdentifier] {
            if configuredEntitlement.isActive {
                return configuredEntitlement
            }
            logger.debug(
                "Entitlement id=\(RevenueCatConfiguration.entitlementIdentifier) present but inactive. product=\(configuredEntitlement.productIdentifier)"
            )
        }

        let fallbackEntitlement = activeEntitlements.first { entitlement in
            entitlement.productIdentifier == RevenueCatConfiguration.yearlyProductIdentifier
                || entitlement.productIdentifier == RevenueCatConfiguration.lifetimeProductIdentifier
        }

        if let fallbackEntitlement {
            logger.notice(
                "Falling back to active entitlement product=\(fallbackEntitlement.productIdentifier) because configured entitlement id=\(RevenueCatConfiguration.entitlementIdentifier) was not found or inactive."
            )
            return fallbackEntitlement
        }

        if let genericEntitlement = activeEntitlements.first {
            logger.notice(
                "Falling back to generic active entitlement id=\(genericEntitlement.identifier) product=\(genericEntitlement.productIdentifier) because configured entitlement id=\(RevenueCatConfiguration.entitlementIdentifier) was not found or inactive."
            )
            return genericEntitlement
        }

        return nil
    }

    private nonisolated static func preferredEntitlementOrder(_ lhs: EntitlementInfo, _ rhs: EntitlementInfo) -> Bool {
        switch (lhs.expirationDate, rhs.expirationDate) {
        case (.none, .some):
            return true
        case (.some, .none):
            return false
        case let (.some(lhsDate), .some(rhsDate)) where lhsDate != rhsDate:
            return lhsDate > rhsDate
        default:
            return lhs.identifier.localizedCompare(rhs.identifier) == .orderedAscending
        }
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

        return ProEntitlementSnapshot(
            plan: plan,
            expirationDate: entitlement.expirationDate,
            willRenew: plan == .yearly && entitlement.willRenew,
            originalPurchaseDate: entitlement.originalPurchaseDate
        )
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

extension Offering {
    func package(for plan: ProPlan) -> Package? {
        switch plan {
        case .yearly:
            return self.annual
                ?? self.availablePackages.first(where: { $0.storeProduct.productIdentifier == plan.productIdentifier })
        case .lifetime:
            return self.lifetime
                ?? self.availablePackages.first(where: { $0.storeProduct.productIdentifier == plan.productIdentifier })
        }
    }
}

struct ProEntitlementSnapshot: Equatable, Sendable {
    let plan: ProPlan
    let expirationDate: Date?
    let willRenew: Bool
    let originalPurchaseDate: Date?

    nonisolated init(
        plan: ProPlan,
        expirationDate: Date?,
        willRenew: Bool = false,
        originalPurchaseDate: Date? = nil
    ) {
        self.plan = plan
        self.expirationDate = expirationDate
        self.willRenew = willRenew
        self.originalPurchaseDate = originalPurchaseDate
    }
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
