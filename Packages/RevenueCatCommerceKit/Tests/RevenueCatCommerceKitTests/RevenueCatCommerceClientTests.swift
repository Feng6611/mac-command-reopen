import Foundation
import RevenueCat
import StoreKit
import XCTest
import os
@testable import RevenueCatCommerceKit

@MainActor
final class RevenueCatCommerceClientTests: XCTestCase {
    private let configuration = CommerceConfiguration(
        apiKey: "test_key",
        entitlementIdentifier: "pro",
        productIdentifiers: [
            .yearly: "com.example.app.pro.yearly",
            .lifetime: "com.example.app.pro.lifetime"
        ],
        requestTimeoutNanoseconds: 1_000_000_000,
        logSubsystem: "RevenueCatCommerceKitTests"
    )

    func testLoadOfferingFallsBackToConfiguredOfferingWhenCurrentHasNoConfiguredProducts() async throws {
        let sdkClient = MockRevenueCatSDKClient()
        sdkClient.loadedOfferings = .init(
            current: makeOffering(identifier: "other", productIdentifiers: ["com.example.other.pro.yearly"]),
            all: [
                "default": makeOffering(
                    identifier: "default",
                    productIdentifiers: [configuration.productIdentifiers[.lifetime]!]
                )
            ]
        )
        let client = RevenueCatCommerceClient(configuration: configuration, sdkClient: sdkClient)
        client.configureIfNeeded()

        let offering = try await client.loadOffering()

        XCTAssertEqual(offering?.identifier, "default")
        XCTAssertEqual(offering?.products.map(\.plan), [.lifetime])
    }

    func testLoadOfferingKeepsCurrentOfferingWhenItHasConfiguredProducts() async throws {
        let sdkClient = MockRevenueCatSDKClient()
        sdkClient.loadedOfferings = .init(
            current: makeOffering(
                identifier: "experiment",
                productIdentifiers: [configuration.productIdentifiers[.yearly]!]
            ),
            all: [
                "default": makeOffering(
                    identifier: "default",
                    productIdentifiers: [configuration.productIdentifiers[.lifetime]!]
                )
            ]
        )
        let client = RevenueCatCommerceClient(configuration: configuration, sdkClient: sdkClient)
        client.configureIfNeeded()

        let offering = try await client.loadOffering()

        XCTAssertEqual(offering?.identifier, "experiment")
        XCTAssertEqual(offering?.products.map(\.plan), [.yearly])
    }

    func testLegacyEntitlementStaysDisabledByDefault() async throws {
        let sdkClient = MockRevenueCatSDKClient()
        let legacySource = MockLegacyPaidAppEntitlementSource()
        legacySource.refreshedLegacyEntitlement = CommerceEntitlement(
            plan: .lifetime,
            productIdentifier: "legacy-paid-app",
            entitlementIdentifier: "legacy",
            expirationDate: nil
        )
        let client = RevenueCatCommerceClient(
            configuration: configuration,
            sdkClient: sdkClient,
            legacyEntitlementSource: legacySource
        )

        let entitlement = try await client.refreshEntitlement()

        XCTAssertNil(entitlement)
        XCTAssertEqual(legacySource.refreshCallCount, 1)
    }

    func testRefreshUsesLegacyEntitlementWhenEnabledAndRevenueCatIsUnavailable() async throws {
        let configuration = CommerceConfiguration(
            apiKey: "",
            entitlementIdentifier: "pro",
            productIdentifiers: [
                .yearly: "com.example.app.pro.yearly",
                .lifetime: "com.example.app.pro.lifetime"
            ],
            legacyPaidApp: .grandfatheredPaidApp(
                cutoffOriginalAppVersion: "1.2.0",
                entitlementIdentifier: "legacy-pro",
                mapsToPlan: .lifetime
            ),
            logSubsystem: "RevenueCatCommerceKitTests"
        )
        let legacyEntitlement = CommerceEntitlement(
            plan: .lifetime,
            productIdentifier: "com.example.app.pro.lifetime",
            entitlementIdentifier: "legacy-pro",
            expirationDate: nil,
            originalPurchaseDate: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let legacySource = MockLegacyPaidAppEntitlementSource()
        legacySource.refreshedLegacyEntitlement = legacyEntitlement
        let client = RevenueCatCommerceClient(
            configuration: configuration,
            sdkClient: MockRevenueCatSDKClient(),
            legacyEntitlementSource: legacySource
        )

        let entitlement = try await client.refreshEntitlement()

        XCTAssertEqual(entitlement, legacyEntitlement)
    }

    func testLegacyGrandfatheringMapsVersionsBeforeCutoffToLifetime() {
        let configuration = legacyConfiguration()
        let purchaseDate = Date(timeIntervalSince1970: 1_700_000_000)

        let entitlement = LegacyPaidAppEntitlementSource.entitlementIfGrandfathered(
            originalAppVersion: "1.1.0",
            originalPurchaseDate: purchaseDate,
            configuration: configuration
        )

        XCTAssertEqual(entitlement, CommerceEntitlement(
            plan: .lifetime,
            productIdentifier: configuration.productIdentifiers[.lifetime]!,
            entitlementIdentifier: "legacy-pro",
            expirationDate: nil,
            willRenew: false,
            originalPurchaseDate: purchaseDate
        ))
    }

    func testLegacyGrandfatheringIgnoresVersionsAtOrAfterCutoff() {
        let configuration = legacyConfiguration()

        XCTAssertNil(LegacyPaidAppEntitlementSource.entitlementIfGrandfathered(
            originalAppVersion: "1.2.0",
            originalPurchaseDate: Date(timeIntervalSince1970: 1_700_000_000),
            configuration: configuration
        ))
    }

    func testRevenueCatEntitlementWinsOverLegacyEntitlement() async throws {
        let sdkClient = MockRevenueCatSDKClient()
        let revenueCatEntitlement = makeCustomerInfo(entitlements: [
            makeEntitlement(
                identifier: configuration.entitlementIdentifier,
                isActive: true,
                productIdentifier: configuration.productIdentifiers[.yearly]!,
                expirationDate: Date(timeIntervalSince1970: 1_800_000_000)
            )
        ])
        sdkClient.loadedCustomerInfo = revenueCatEntitlement
        let legacySource = MockLegacyPaidAppEntitlementSource()
        legacySource.refreshedLegacyEntitlement = CommerceEntitlement(
            plan: .lifetime,
            productIdentifier: configuration.productIdentifiers[.lifetime]!,
            entitlementIdentifier: "legacy-pro",
            expirationDate: nil
        )
        let client = RevenueCatCommerceClient(
            configuration: configuration,
            sdkClient: sdkClient,
            legacyEntitlementSource: legacySource
        )
        client.configureIfNeeded()

        let entitlement = try await client.refreshEntitlement()

        XCTAssertEqual(entitlement?.plan, .yearly)
        XCTAssertEqual(entitlement?.productIdentifier, configuration.productIdentifiers[.yearly])
    }

    private func makeOffering(identifier: String, productIdentifiers: [String]) -> Offering {
        let packages = productIdentifiers.map { productIdentifier in
            Package(
                identifier: productIdentifier,
                packageType: .custom,
                storeProduct: StoreProduct(sk1Product: MockSKProduct(productIdentifier: productIdentifier)),
                offeringIdentifier: identifier,
                webCheckoutUrl: nil
            )
        }

        return Offering(
            identifier: identifier,
            serverDescription: identifier,
            availablePackages: packages,
            webCheckoutUrl: nil
        )
    }

    private func legacyConfiguration() -> CommerceConfiguration {
        CommerceConfiguration(
            apiKey: "",
            entitlementIdentifier: "pro",
            productIdentifiers: [
                .yearly: "com.example.app.pro.yearly",
                .lifetime: "com.example.app.pro.lifetime"
            ],
            legacyPaidApp: .grandfatheredPaidApp(
                cutoffOriginalAppVersion: "1.2.0",
                entitlementIdentifier: "legacy-pro",
                mapsToPlan: .lifetime
            ),
            logSubsystem: "RevenueCatCommerceKitTests"
        )
    }
}

private final class MockRevenueCatSDKClient: RevenueCatSDKClient {
    var cachedCustomerInfo: CustomerInfo?
    var customerInfoDidChange: ((CustomerInfo) -> Void)?
    var loadedOfferings = RevenueCatSDKOfferings(current: nil, all: [:])
    var loadedCustomerInfo: CustomerInfo?
    var didConfigure = false

    func configure(with configuration: CommerceConfiguration) {
        didConfigure = true
    }

    func offerings() async throws -> RevenueCatSDKOfferings {
        loadedOfferings
    }

    func customerInfo(fetchPolicy: CacheFetchPolicy) async throws -> CustomerInfo {
        guard let loadedCustomerInfo else {
            throw CommercePurchaseError.unknown("No customer info configured in this test double.")
        }

        return loadedCustomerInfo
    }

    func purchase(package: Package) async throws -> PurchaseResultData {
        throw CommercePurchaseError.unknown("Not implemented in this test double.")
    }

    func restorePurchases() async throws -> CustomerInfo {
        throw CommercePurchaseError.unknown("Not implemented in this test double.")
    }
}

@MainActor
private final class MockLegacyPaidAppEntitlementSource: LegacyPaidAppEntitlementProviding {
    var cachedLegacyEntitlement: CommerceEntitlement?
    var refreshedLegacyEntitlement: CommerceEntitlement?
    var refreshCallCount = 0

    func refreshLegacyEntitlement(configuration: CommerceConfiguration, logger: Logger) async -> CommerceEntitlement? {
        refreshCallCount += 1
        guard configuration.legacyPaidApp.isEnabled else {
            cachedLegacyEntitlement = nil
            return nil
        }

        cachedLegacyEntitlement = refreshedLegacyEntitlement
        return refreshedLegacyEntitlement
    }
}

private let originalPurchaseDate = Date(timeIntervalSince1970: 1_700_000_000)

private func makeEntitlement(
    identifier: String,
    isActive: Bool,
    productIdentifier: String,
    expirationDate: Date?,
    willRenew: Bool? = nil
) -> EntitlementInfo {
    .init(
        identifier: identifier,
        isActive: isActive,
        willRenew: willRenew ?? (expirationDate != nil),
        periodType: .normal,
        latestPurchaseDate: originalPurchaseDate,
        originalPurchaseDate: originalPurchaseDate,
        expirationDate: expirationDate,
        store: .macAppStore,
        productIdentifier: productIdentifier,
        isSandbox: true,
        ownershipType: .purchased
    )
}

private func makeCustomerInfo(entitlements: [EntitlementInfo]) -> CustomerInfo {
    let requestDate = Date(timeIntervalSince1970: 1_700_000_100)
    let entitlementsByIdentifier = Dictionary(uniqueKeysWithValues: entitlements.map { ($0.identifier, $0) })
    let expirationDatesByProductID = Dictionary(
        uniqueKeysWithValues: entitlements.compactMap { entitlement in
            entitlement.expirationDate.map { (entitlement.productIdentifier, $0) }
        }
    )
    let purchaseDatesByProductID = Dictionary(
        uniqueKeysWithValues: entitlements.compactMap { entitlement in
            entitlement.latestPurchaseDate.map { (entitlement.productIdentifier, $0) }
        }
    )

    return CustomerInfo(
        entitlements: .init(entitlements: entitlementsByIdentifier),
        expirationDatesByProductId: expirationDatesByProductID,
        purchaseDatesByProductId: purchaseDatesByProductID,
        allPurchasedProductIds: Set(entitlements.map(\.productIdentifier)),
        requestDate: requestDate,
        firstSeen: requestDate,
        originalAppUserId: "user"
    )
}

private final class MockSKProduct: SKProduct, @unchecked Sendable {
    private let resolvedProductIdentifier: String

    init(productIdentifier: String) {
        self.resolvedProductIdentifier = productIdentifier
        super.init()
    }

    override var productIdentifier: String {
        resolvedProductIdentifier
    }

    override var localizedTitle: String {
        resolvedProductIdentifier
    }

    override var price: NSDecimalNumber {
        2.99
    }

    override var priceLocale: Locale {
        Locale(identifier: "en_US")
    }
}
