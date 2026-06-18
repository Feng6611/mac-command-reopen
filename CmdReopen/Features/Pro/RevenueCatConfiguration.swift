//
//  RevenueCatConfiguration.swift
//  CmdReopen
//
//  Created by Codex on 2026/4/26.
//

import Foundation
import RevenueCatCommerceKit

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
            apiKey: apiKey,
            entitlementIdentifier: entitlementIdentifier,
            offeringIdentifier: offeringIdentifier,
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
}
