import Foundation
import RevenueCat
import XCTest
@testable import RevenueCatCommerceKit

final class RevenueCatSnapshotMapperTests: XCTestCase {
    private let originalPurchaseDate = Date(timeIntervalSince1970: 1_700_000_000)
    private let configuration = CommerceConfiguration(
        apiKey: "test_key",
        entitlementIdentifier: "pro",
        productIdentifiers: [
            .yearly: "com.example.app.pro.yearly",
            .lifetime: "com.example.app.pro.lifetime"
        ],
        logSubsystem: "RevenueCatCommerceKitTests"
    )

    func testParserPrefersConfiguredEntitlementIdentifier() {
        let expirationDate = Date(timeIntervalSince1970: 1_800_000_000)
        let customerInfo = makeCustomerInfo(entitlements: [
            makeEntitlement(
                identifier: configuration.entitlementIdentifier,
                isActive: true,
                productIdentifier: configuration.productIdentifiers[.lifetime]!,
                expirationDate: nil
            ),
            makeEntitlement(
                identifier: "other",
                isActive: true,
                productIdentifier: configuration.productIdentifiers[.yearly]!,
                expirationDate: expirationDate
            )
        ])

        let entitlement = RevenueCatSnapshotMapper.makeEntitlement(
            from: customerInfo,
            configuration: configuration,
            logger: .init(subsystem: "RevenueCatCommerceKitTests", category: "Tests")
        )

        XCTAssertEqual(entitlement, CommerceEntitlement(
            plan: .lifetime,
            productIdentifier: configuration.productIdentifiers[.lifetime]!,
            entitlementIdentifier: configuration.entitlementIdentifier,
            expirationDate: nil,
            willRenew: false,
            originalPurchaseDate: originalPurchaseDate
        ))
    }

    func testParserFallsBackToActiveProductIdentifiersWhenEntitlementIdIsMissing() {
        let expirationDate = Date(timeIntervalSince1970: 1_800_000_000)
        let customerInfo = makeCustomerInfo(entitlements: [
            makeEntitlement(
                identifier: "fallback-yearly",
                isActive: true,
                productIdentifier: configuration.productIdentifiers[.yearly]!,
                expirationDate: expirationDate
            )
        ])

        let entitlement = RevenueCatSnapshotMapper.makeEntitlement(
            from: customerInfo,
            configuration: configuration,
            logger: .init(subsystem: "RevenueCatCommerceKitTests", category: "Tests")
        )

        XCTAssertEqual(entitlement, CommerceEntitlement(
            plan: .yearly,
            productIdentifier: configuration.productIdentifiers[.yearly]!,
            entitlementIdentifier: "fallback-yearly",
            expirationDate: expirationDate,
            willRenew: true,
            originalPurchaseDate: originalPurchaseDate
        ))
    }

    func testParserFallsBackToAnyActiveEntitlementWhenIdentifiersDrift() {
        let expirationDate = Date(timeIntervalSince1970: 1_800_000_000)
        let customerInfo = makeCustomerInfo(entitlements: [
            makeEntitlement(
                identifier: "promo-pro",
                isActive: true,
                productIdentifier: "custom.subscription",
                expirationDate: expirationDate
            )
        ])

        let entitlement = RevenueCatSnapshotMapper.makeEntitlement(
            from: customerInfo,
            configuration: configuration,
            logger: .init(subsystem: "RevenueCatCommerceKitTests", category: "Tests")
        )

        XCTAssertEqual(entitlement, CommerceEntitlement(
            plan: .yearly,
            productIdentifier: "custom.subscription",
            entitlementIdentifier: "promo-pro",
            expirationDate: expirationDate,
            willRenew: true,
            originalPurchaseDate: originalPurchaseDate
        ))
    }

    func testParserIgnoresInactiveConfiguredEntitlements() {
        let customerInfo = makeCustomerInfo(entitlements: [
            makeEntitlement(
                identifier: configuration.entitlementIdentifier,
                isActive: false,
                productIdentifier: configuration.productIdentifiers[.yearly]!,
                expirationDate: Date(timeIntervalSince1970: 1_800_000_000)
            )
        ])

        let entitlement = RevenueCatSnapshotMapper.makeEntitlement(
            from: customerInfo,
            configuration: configuration,
            logger: .init(subsystem: "RevenueCatCommerceKitTests", category: "Tests")
        )

        XCTAssertNil(entitlement)
    }

    func testParserInfersLifetimeForUnknownProductsWithoutExpiration() {
        let customerInfo = makeCustomerInfo(entitlements: [
            makeEntitlement(
                identifier: configuration.entitlementIdentifier,
                isActive: true,
                productIdentifier: "custom.product",
                expirationDate: nil
            )
        ])

        let entitlement = RevenueCatSnapshotMapper.makeEntitlement(
            from: customerInfo,
            configuration: configuration,
            logger: .init(subsystem: "RevenueCatCommerceKitTests", category: "Tests")
        )

        XCTAssertEqual(entitlement?.plan, .lifetime)
        XCTAssertEqual(entitlement?.willRenew, false)
    }

    func testParserPreservesCancelledYearlyRenewalState() {
        let expirationDate = Date(timeIntervalSince1970: 1_800_000_000)
        let customerInfo = makeCustomerInfo(entitlements: [
            makeEntitlement(
                identifier: configuration.entitlementIdentifier,
                isActive: true,
                productIdentifier: configuration.productIdentifiers[.yearly]!,
                expirationDate: expirationDate,
                willRenew: false
            )
        ])

        let entitlement = RevenueCatSnapshotMapper.makeEntitlement(
            from: customerInfo,
            configuration: configuration,
            logger: .init(subsystem: "RevenueCatCommerceKitTests", category: "Tests")
        )

        XCTAssertEqual(entitlement?.plan, .yearly)
        XCTAssertEqual(entitlement?.willRenew, false)
    }

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

        return .init(
            entitlements: .init(entitlements: entitlementsByIdentifier),
            expirationDatesByProductId: expirationDatesByProductID,
            purchaseDatesByProductId: purchaseDatesByProductID,
            allPurchasedProductIds: Set(entitlements.map(\.productIdentifier)),
            requestDate: requestDate,
            firstSeen: requestDate,
            originalAppUserId: "test-user"
        )
    }
}

