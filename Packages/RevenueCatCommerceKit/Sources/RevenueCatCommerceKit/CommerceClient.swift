import Foundation

@MainActor
public protocol CommerceClient: AnyObject {
    var cachedEntitlement: CommerceEntitlement? { get }
    var entitlementDidChange: ((CommerceEntitlement?) -> Void)? { get set }

    func configureIfNeeded()
    func refreshEntitlement() async throws -> CommerceEntitlement?
    func loadOffering() async throws -> CommerceOffering?
    func purchase(_ plan: CommercePlan) async throws -> CommerceEntitlement?
    func restorePurchases() async throws -> CommerceEntitlement?
}
