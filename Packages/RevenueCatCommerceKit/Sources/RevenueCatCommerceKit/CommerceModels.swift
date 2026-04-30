import Foundation

public enum CommercePlan: String, CaseIterable, Equatable, Sendable {
    case yearly
    case lifetime
}

public struct CommerceProduct: Equatable, Identifiable, Sendable {
    public let plan: CommercePlan
    public let productIdentifier: String
    public let displayPrice: String
    public let isAvailable: Bool

    public var id: CommercePlan { plan }

    public init(
        plan: CommercePlan,
        productIdentifier: String,
        displayPrice: String,
        isAvailable: Bool
    ) {
        self.plan = plan
        self.productIdentifier = productIdentifier
        self.displayPrice = displayPrice
        self.isAvailable = isAvailable
    }
}

public struct CommerceOffering: Equatable, Sendable {
    public let identifier: String
    public let products: [CommerceProduct]

    public init(identifier: String, products: [CommerceProduct]) {
        self.identifier = identifier
        self.products = products
    }

    public var isEmpty: Bool {
        products.isEmpty
    }

    public func product(for plan: CommercePlan) -> CommerceProduct? {
        products.first { $0.plan == plan }
    }
}

public struct CommerceEntitlement: Equatable, Sendable {
    public let plan: CommercePlan
    public let productIdentifier: String
    public let entitlementIdentifier: String
    public let expirationDate: Date?
    public let willRenew: Bool
    public let originalPurchaseDate: Date?

    public init(
        plan: CommercePlan,
        productIdentifier: String,
        entitlementIdentifier: String,
        expirationDate: Date?,
        willRenew: Bool = false,
        originalPurchaseDate: Date? = nil
    ) {
        self.plan = plan
        self.productIdentifier = productIdentifier
        self.entitlementIdentifier = entitlementIdentifier
        self.expirationDate = expirationDate
        self.willRenew = willRenew
        self.originalPurchaseDate = originalPurchaseDate
    }
}
