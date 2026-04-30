import XCTest
@testable import RevenueCatCommerceKit

final class CommerceConfigurationTests: XCTestCase {
    func testStandardProBuildsProductIdentifiersFromBundleIdentifier() throws {
        let configuration = CommerceConfiguration.standardPro(
            apiKey: "test_key",
            bundleIdentifier: "com.example.MyApp"
        )

        XCTAssertEqual(configuration.entitlementIdentifier, "pro")
        XCTAssertEqual(configuration.offeringIdentifier, "default")
        XCTAssertEqual(try configuration.productIdentifier(for: .yearly), "com.example.MyApp.pro.yearly")
        XCTAssertEqual(try configuration.productIdentifier(for: .lifetime), "com.example.MyApp.pro.lifetime")
    }

    func testExplicitConfigurationKeepsSkuValues() throws {
        let configuration = CommerceConfiguration(
            apiKey: "test_key",
            entitlementIdentifier: "pro",
            productIdentifiers: [
                .yearly: "yearly.sku",
                .lifetime: "lifetime.sku"
            ]
        )

        XCTAssertEqual(try configuration.productIdentifier(for: .yearly), "yearly.sku")
        XCTAssertEqual(try configuration.productIdentifier(for: .lifetime), "lifetime.sku")
    }

    func testMissingProductIdentifierThrows() {
        let configuration = CommerceConfiguration(
            apiKey: "test_key",
            entitlementIdentifier: "pro",
            productIdentifiers: [.yearly: "yearly.sku"]
        )

        XCTAssertThrowsError(try configuration.productIdentifier(for: .lifetime)) { error in
            XCTAssertEqual(error as? CommercePurchaseError, .productIdentifierMissing(.lifetime))
        }
    }
}
