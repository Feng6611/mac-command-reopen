//
//  RevenueCatConfiguration.swift
//  CmdReopen
//
//  Created by Codex on 2026/4/26.
//

import Foundation
import KikiCommerceCore
import KikiRevenueCat

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
    nonisolated static let grandfatheringCutoffVersion = "1.2.0"

    nonisolated static var commerceConfiguration: CommerceConfiguration {
        CommerceConfiguration(
            entitlementIdentifier: entitlementIdentifier,
            productIdentifiers: [
                .yearly: yearlyProductIdentifier,
                .lifetime: lifetimeProductIdentifier
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
                )
            ],
            defaultPlanID: CommercePlan.lifetime.rawValue,
            commerceConfiguration: commerceConfiguration,
            trialPolicy: .autoStart(duration: 2 * 24 * 60 * 60),
            storageKeys: KikiAccessStorageKeys(
                trialStartedAt: "cmdreopenTrialStartDate",
                debugProAccessOverride: "CmdReopen.Access.debugOverride",
                usageCountPrefix: "CmdReopen.Access.usage"
            )
        )
    }
}
