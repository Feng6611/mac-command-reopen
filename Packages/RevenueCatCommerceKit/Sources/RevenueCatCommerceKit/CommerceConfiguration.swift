import Foundation
import RevenueCat

public enum CommerceEntitlementMatchingPolicy: Equatable, Sendable {
    case configuredEntitlementOrProductOnly
    case allowAnyActiveEntitlement
}

public struct CommerceConfiguration: Sendable {
    public let apiKey: String
    public let entitlementIdentifier: String
    public let offeringIdentifier: String
    public let productIdentifiers: [CommercePlan: String]
    public let entitlementMatchingPolicy: CommerceEntitlementMatchingPolicy
    public let requestTimeoutNanoseconds: UInt64
    public let invalidReceiptRecoveryDelayNanoseconds: UInt64
    public let allowsTestAPIKeyInRelease: Bool
    public let showStoreMessagesAutomatically: Bool
    public let legacyPaidApp: LegacyPaidAppConfiguration
    public let logSubsystem: String
    public let logCategory: String

    public init(
        apiKey: String,
        entitlementIdentifier: String,
        offeringIdentifier: String = "default",
        productIdentifiers: [CommercePlan: String],
        entitlementMatchingPolicy: CommerceEntitlementMatchingPolicy = .allowAnyActiveEntitlement,
        requestTimeoutNanoseconds: UInt64 = 4_000_000_000,
        invalidReceiptRecoveryDelayNanoseconds: UInt64 = 1_000_000_000,
        allowsTestAPIKeyInRelease: Bool = false,
        showStoreMessagesAutomatically: Bool = true,
        legacyPaidApp: LegacyPaidAppConfiguration = .disabled,
        logSubsystem: String = Bundle.main.bundleIdentifier ?? "RevenueCatCommerceKit",
        logCategory: String = "Commerce"
    ) {
        self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.entitlementIdentifier = entitlementIdentifier
        self.offeringIdentifier = offeringIdentifier
        self.productIdentifiers = productIdentifiers
        self.entitlementMatchingPolicy = entitlementMatchingPolicy
        self.requestTimeoutNanoseconds = requestTimeoutNanoseconds
        self.invalidReceiptRecoveryDelayNanoseconds = invalidReceiptRecoveryDelayNanoseconds
        self.allowsTestAPIKeyInRelease = allowsTestAPIKeyInRelease
        self.showStoreMessagesAutomatically = showStoreMessagesAutomatically
        self.legacyPaidApp = legacyPaidApp
        self.logSubsystem = logSubsystem
        self.logCategory = logCategory
    }

    public static func standardPro(
        apiKey: String,
        bundleIdentifier: String,
        entitlementIdentifier: String = "pro",
        offeringIdentifier: String = "default",
        productSuffix: String = "pro"
    ) -> Self {
        Self(
            apiKey: apiKey,
            entitlementIdentifier: entitlementIdentifier,
            offeringIdentifier: offeringIdentifier,
            productIdentifiers: [
                .yearly: "\(bundleIdentifier).\(productSuffix).yearly",
                .lifetime: "\(bundleIdentifier).\(productSuffix).lifetime"
            ],
            logSubsystem: bundleIdentifier
        )
    }

    public static func standardProFromInfoDictionary(
        apiKeyInfoDictionaryKey: String,
        bundle: Bundle = .main,
        entitlementIdentifier: String = "pro",
        offeringIdentifier: String = "default",
        productSuffix: String = "pro"
    ) -> Self {
        let bundleIdentifier = bundle.bundleIdentifier ?? "RevenueCatCommerceKit"
        let apiKey = (bundle.object(forInfoDictionaryKey: apiKeyInfoDictionaryKey) as? String) ?? ""

        return standardPro(
            apiKey: apiKey,
            bundleIdentifier: bundleIdentifier,
            entitlementIdentifier: entitlementIdentifier,
            offeringIdentifier: offeringIdentifier,
            productSuffix: productSuffix
        )
    }

    public func productIdentifier(for plan: CommercePlan) throws -> String {
        guard let productIdentifier = productIdentifiers[plan], !productIdentifier.isEmpty else {
            throw CommercePurchaseError.productIdentifierMissing(plan)
        }

        return productIdentifier
    }
}
