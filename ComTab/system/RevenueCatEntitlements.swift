//
//  RevenueCatEntitlements.swift
//  ComTab
//
//  Created by Codex on 2026/4/26.
//

import Foundation
import RevenueCatCommerceKit

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

    nonisolated static var commerceConfiguration: CommerceConfiguration {
        CommerceConfiguration(
            apiKey: apiKey,
            entitlementIdentifier: entitlementIdentifier,
            offeringIdentifier: offeringIdentifier,
            productIdentifiers: [
                .yearly: yearlyProductIdentifier,
                .lifetime: lifetimeProductIdentifier
            ],
            logSubsystem: Bundle.main.bundleIdentifier ?? "com.dev.kkuk.CmdReopen",
            logCategory: "Purchase"
        )
    }
}

extension ProPlan {
    var commercePlan: CommercePlan {
        switch self {
        case .yearly:
            .yearly
        case .lifetime:
            .lifetime
        }
    }
}

extension CommercePlan {
    var proPlan: ProPlan {
        switch self {
        case .yearly:
            .yearly
        case .lifetime:
            .lifetime
        }
    }
}

extension CommerceOffering {
    var proOfferingSnapshot: ProOfferingSnapshot {
        var metadata: [ProPlan: ProPlanPackageMetadata] = [:]

        for product in products {
            let plan = product.plan.proPlan
            metadata[plan] = ProPlanPackageMetadata(
                displayPrice: product.displayPrice,
                billingDetail: plan == .yearly ? String(localized: "per year") : String(localized: "once"),
                isAvailable: product.isAvailable
            )
        }

        return ProOfferingSnapshot(packageMetadata: metadata)
    }
}

extension CommerceEntitlement {
    var proEntitlementSnapshot: ProEntitlementSnapshot {
        ProEntitlementSnapshot(
            plan: plan.proPlan,
            expirationDate: expirationDate,
            willRenew: willRenew,
            originalPurchaseDate: originalPurchaseDate
        )
    }
}
