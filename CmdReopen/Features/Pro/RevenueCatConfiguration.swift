//
//  RevenueCatConfiguration.swift
//  CmdReopen
//
//  Created by Codex on 2026/4/26.
//

import Foundation
import KikiCommerceCore
import KikiRevenueCat

extension CommercePlan {
    /// Command Reopen's win-back plan. Same entitlement as `.lifetime`, lower
    /// price, offered only when the trial ended without a purchase.
    nonisolated static let winbackLifetime = CommercePlan("winbackLifetime")
}

enum RevenueCatConfiguration {
    nonisolated static let apiKeyInfoKey = "CmdReopenRevenueCatAPIKey"
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
    /// The win-back SKU: the same lifetime unlock at 20% off, sold only from
    /// the retention card during its two-day window. A separate product
    /// rather than a code because macOS has no in-app redemption sheet — a
    /// code would send the user hunting for the App Store's redeem screen at
    /// the exact moment they are already leaving.
    nonisolated static let winbackLifetimeProductIdentifier = "com.dev.kkuk.CommandReopen.lifetime20"
    nonisolated static let grandfatheringCutoffVersion = "1.2.0"
    nonisolated static let trialDuration: TimeInterval = 14 * 24 * 60 * 60

    nonisolated static var commerceConfiguration: CommerceConfiguration {
        CommerceConfiguration(
            entitlementIdentifier: entitlementIdentifier,
            productIdentifiers: [
                .yearly: yearlyProductIdentifier,
                .lifetime: lifetimeProductIdentifier,
                .winbackLifetime: winbackLifetimeProductIdentifier
            ],
            entitlementMatchingPolicy: .configuredEntitlementOrProductOnly,
            legacyPaidApp: .grandfatheredPaidApp(
                cutoffOriginalAppVersion: grandfatheringCutoffVersion,
                entitlementIdentifier: entitlementIdentifier,
                mapsToPlan: .lifetime,
                productIdentifier: lifetimeProductIdentifier
            ),
            logSubsystem: Bundle.main.bundleIdentifier ?? "com.dev.kkuk.CmdReopen",
            logCategory: "Purchase"
        )
    }

    nonisolated static var providerConfiguration: KikiRevenueCat.RevenueCatConfiguration {
        KikiRevenueCat.RevenueCatConfiguration(
            apiKey: apiKey,
            offeringIdentifier: offeringIdentifier
        )
    }

    nonisolated static var accessConfiguration: KikiAccessConfiguration {
        KikiAccessConfiguration(
            plans: [
                KikiAccessPlan(
                    id: CommercePlan.yearly.rawValue,
                    commercePlan: .yearly,
                    title: String(localized: "Yearly"),
                    fallbackDisplayPrice: "$5.99",
                    billingDetail: String(localized: "per year"),
                    subtitle: String(localized: "Auto-renews annually")
                ),
                KikiAccessPlan(
                    id: CommercePlan.lifetime.rawValue,
                    commercePlan: .lifetime,
                    title: String(localized: "Lifetime"),
                    fallbackDisplayPrice: "$10.99",
                    billingDetail: String(localized: "once"),
                    subtitle: String(localized: "Pay once, use forever"),
                    badge: String(localized: "Best Value")
                ),
                // Sold only from the retention card; `visiblePaywallPlanIDs`
                // keeps it off the regular paywall so the discount never sits
                // beside the price it undercuts.
                KikiAccessPlan(
                    id: CommercePlan.winbackLifetime.rawValue,
                    commercePlan: .winbackLifetime,
                    title: String(localized: "Lifetime"),
                    fallbackDisplayPrice: "$8.79",
                    billingDetail: String(localized: "once"),
                    subtitle: String(localized: "Pay once, use forever")
                )
            ],
            defaultPlanID: CommercePlan.lifetime.rawValue,
            commerceConfiguration: commerceConfiguration,
            trialPolicy: .autoStart(duration: trialDuration),
            storageKeys: KikiAccessStorageKeys(
                trialStartedAt: "cmdreopenTrialStartDate",
                debugProAccessOverride: "CmdReopen.Access.debugOverride",
                usageCountPrefix: "CmdReopen.Access.usage"
            )
        )
    }

    /// Plans the regular paywall lists. Excludes the win-back SKU, which is
    /// sold only from the retention card.
    nonisolated static var visiblePaywallPlanIDs: [String] {
        [CommercePlan.yearly.rawValue, CommercePlan.lifetime.rawValue]
    }
}
