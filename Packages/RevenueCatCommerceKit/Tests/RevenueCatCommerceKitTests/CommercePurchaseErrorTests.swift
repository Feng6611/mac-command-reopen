import Foundation
import RevenueCat
import XCTest
@testable import RevenueCatCommerceKit

final class CommercePurchaseErrorTests: XCTestCase {
    func testRevenueCatConfigurationErrorsMapToNotConfigured() {
        let error = NSError(
            domain: RevenueCat.ErrorCode.errorDomain,
            code: RevenueCat.ErrorCode.configurationError.rawValue
        )

        XCTAssertEqual(CommercePurchaseError(error: error), .notConfigured)
    }

    func testRevenueCatInvalidReceiptErrorsMapToInvalidReceipt() {
        let error = NSError(
            domain: RevenueCat.ErrorCode.errorDomain,
            code: RevenueCat.ErrorCode.invalidReceiptError.rawValue
        )

        XCTAssertEqual(CommercePurchaseError(error: error), .invalidReceipt)
    }

    func testNonRevenueCatDomainsDoNotGetRemappedByRawCodeAlone() {
        let error = NSError(
            domain: NSCocoaErrorDomain,
            code: RevenueCat.ErrorCode.configurationError.rawValue,
            userInfo: [NSLocalizedDescriptionKey: "Cocoa failure"]
        )

        XCTAssertEqual(CommercePurchaseError(error: error), .unknown("Cocoa failure"))
    }
}
