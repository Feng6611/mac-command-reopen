import Foundation
import RevenueCat
import os

enum RevenueCatSnapshotMapper {
    nonisolated static func makeEntitlement(
        from customerInfo: CustomerInfo?,
        configuration: CommerceConfiguration,
        logger: Logger
    ) -> CommerceEntitlement? {
        guard let customerInfo else {
            return nil
        }

        guard let entitlement = resolveActiveEntitlement(
            from: customerInfo,
            configuration: configuration,
            logger: logger
        ) else {
            logMissingActiveEntitlement(customerInfo: customerInfo, configuration: configuration, logger: logger)
            return nil
        }

        let plan = resolvePlan(for: entitlement, configuration: configuration)

        logger.notice(
            "Mapped active entitlement id=\(entitlement.identifier) product=\(entitlement.productIdentifier) plan=\(plan.rawValue)"
        )

        return CommerceEntitlement(
            plan: plan,
            productIdentifier: entitlement.productIdentifier,
            entitlementIdentifier: entitlement.identifier,
            expirationDate: entitlement.expirationDate,
            willRenew: plan == .yearly && entitlement.willRenew,
            originalPurchaseDate: entitlement.originalPurchaseDate
        )
    }

    nonisolated static func resolveActiveEntitlement(
        from customerInfo: CustomerInfo,
        configuration: CommerceConfiguration,
        logger: Logger
    ) -> EntitlementInfo? {
        let activeEntitlements = customerInfo.entitlements.all.values
            .filter(\.isActive)
            .sorted(by: preferredEntitlementOrder)

        if let configuredEntitlement = customerInfo.entitlements.all[configuration.entitlementIdentifier] {
            if configuredEntitlement.isActive {
                return configuredEntitlement
            }

            logger.debug(
                "Entitlement id=\(configuration.entitlementIdentifier) present but inactive. product=\(configuredEntitlement.productIdentifier)"
            )
        }

        let configuredProductIDs = Set(configuration.productIdentifiers.values)
        if let fallbackEntitlement = activeEntitlements.first(where: { configuredProductIDs.contains($0.productIdentifier) }) {
            logger.notice(
                "Falling back to active entitlement product=\(fallbackEntitlement.productIdentifier) because configured entitlement id=\(configuration.entitlementIdentifier) was not found or inactive."
            )
            return fallbackEntitlement
        }

        switch configuration.entitlementMatchingPolicy {
        case .configuredEntitlementOrProductOnly:
            return nil
        case .allowAnyActiveEntitlement:
            if let genericEntitlement = activeEntitlements.first {
                logger.notice(
                    "Falling back to generic active entitlement id=\(genericEntitlement.identifier) product=\(genericEntitlement.productIdentifier) because configured entitlement id=\(configuration.entitlementIdentifier) was not found or inactive."
                )
                return genericEntitlement
            }
        }

        return nil
    }

    nonisolated static func makeOffering(
        from offering: Offering,
        configuration: CommerceConfiguration
    ) -> CommerceOffering {
        var products: [CommerceProduct] = []

        for plan in CommercePlan.allCases {
            guard let package = offering.package(for: plan, configuration: configuration) else {
                continue
            }

            products.append(
                CommerceProduct(
                    plan: plan,
                    productIdentifier: package.storeProduct.productIdentifier,
                    displayPrice: package.storeProduct.localizedPriceString,
                    isAvailable: true
                )
            )
        }

        return CommerceOffering(identifier: offering.identifier, products: products)
    }

    private nonisolated static func resolvePlan(
        for entitlement: EntitlementInfo,
        configuration: CommerceConfiguration
    ) -> CommercePlan {
        if entitlement.productIdentifier == configuration.productIdentifiers[.lifetime] {
            return .lifetime
        }

        if entitlement.productIdentifier == configuration.productIdentifiers[.yearly] {
            return .yearly
        }

        return entitlement.expirationDate == nil ? .lifetime : .yearly
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

    private nonisolated static func logMissingActiveEntitlement(
        customerInfo: CustomerInfo,
        configuration: CommerceConfiguration,
        logger: Logger
    ) {
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
                "Expected entitlement id=\(configuration.entitlementIdentifier) not found. activeEntitlements=[\(activeEntitlementIdentifiers)] activeSubscriptions=[\(activeSubscriptionIdentifiers)]"
            )
        }
    }
}

extension Offering {
    func package(for plan: CommercePlan, configuration: CommerceConfiguration) -> Package? {
        guard let productIdentifier = configuration.productIdentifiers[plan] else {
            return nil
        }

        return availablePackages.first { $0.storeProduct.productIdentifier == productIdentifier }
    }

    func hasConfiguredProducts(configuration: CommerceConfiguration) -> Bool {
        CommercePlan.allCases.contains { package(for: $0, configuration: configuration) != nil }
    }
}
