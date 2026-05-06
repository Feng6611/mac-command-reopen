import RevenueCatCommerceKit
import Testing
@testable import Command_Reopen

struct ProPurchaseErrorTests {
    @Test("Commerce configuration errors map to not configured")
    func configurationErrorMapsToNotConfigured() {
        #expect(ProPurchaseError(error: CommercePurchaseError.invalidConfiguration("Missing key")) == .notConfigured)
    }

    @Test("Commerce invalid receipt errors map to invalid receipt")
    func invalidReceiptMapsToInvalidReceipt() {
        #expect(ProPurchaseError(error: CommercePurchaseError.invalidReceipt) == .invalidReceipt)
    }

    @Test("Commerce package errors preserve the failed plan")
    func packageErrorsPreservePlan() {
        #expect(ProPurchaseError(error: CommercePurchaseError.productIdentifierMissing(.lifetime)) == .packageNotFound(.lifetime))
    }
}
