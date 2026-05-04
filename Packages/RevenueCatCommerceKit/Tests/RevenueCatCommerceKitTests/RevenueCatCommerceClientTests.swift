import Foundation
import RevenueCat
import StoreKit
import XCTest
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
}

private final class MockRevenueCatSDKClient: RevenueCatSDKClient {
    var cachedCustomerInfo: CustomerInfo?
    var customerInfoDidChange: ((CustomerInfo) -> Void)?
    var loadedOfferings = RevenueCatSDKOfferings(current: nil, all: [:])
    var didConfigure = false

    func configure(with configuration: CommerceConfiguration) {
        didConfigure = true
    }

    func offerings() async throws -> RevenueCatSDKOfferings {
        loadedOfferings
    }

    func customerInfo(fetchPolicy: CacheFetchPolicy) async throws -> CustomerInfo {
        throw CommercePurchaseError.unknown("Not implemented in this test double.")
    }

    func purchase(package: Package) async throws -> PurchaseResultData {
        throw CommercePurchaseError.unknown("Not implemented in this test double.")
    }

    func restorePurchases() async throws -> CustomerInfo {
        throw CommercePurchaseError.unknown("Not implemented in this test double.")
    }
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
