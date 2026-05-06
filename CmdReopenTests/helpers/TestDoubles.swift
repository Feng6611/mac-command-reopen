import Combine
import Foundation
import RevenueCatCommerceKit
@testable import Command_Reopen

final class MockCommerceStateSource: CommerceStateSource {
    var entitlementState: AccessEntitlementState
    var isFirstLaunch: Bool
    var shouldOpenProSettings: Bool

    private let entitlementSubject: CurrentValueSubject<AccessEntitlementState, Never>
    private let promptSubject: CurrentValueSubject<Bool, Never>

    init(
        entitlementState: AccessEntitlementState = .unrestricted,
        isFirstLaunch: Bool = false,
        shouldOpenProSettings: Bool = false
    ) {
        self.entitlementState = entitlementState
        self.isFirstLaunch = isFirstLaunch
        self.shouldOpenProSettings = shouldOpenProSettings
        self.entitlementSubject = CurrentValueSubject(entitlementState)
        self.promptSubject = CurrentValueSubject(shouldOpenProSettings)
    }

    var entitlementStatePublisher: AnyPublisher<AccessEntitlementState, Never> {
        entitlementSubject.eraseToAnyPublisher()
    }

    var proSettingsPromptPublisher: AnyPublisher<Bool, Never> {
        promptSubject.eraseToAnyPublisher()
    }

    func configureIfNeeded() {}

    func refresh() async {}

    func markPromptHandled() {
        shouldOpenProSettings = false
        promptSubject.send(false)
    }

    func update(entitlementState: AccessEntitlementState) {
        self.entitlementState = entitlementState
        entitlementSubject.send(entitlementState)
    }

    func updatePrompt(_ shouldOpen: Bool) {
        shouldOpenProSettings = shouldOpen
        promptSubject.send(shouldOpen)
    }
}

@MainActor
final class MockCommerceClient: CommerceClient {
    var cachedEntitlement: CommerceEntitlement?
    var entitlementDidChange: ((CommerceEntitlement?) -> Void)?

    var currentOffering: CommerceOffering?
    var fetchedEntitlement: CommerceEntitlement?
    var fetchedEntitlements: [CommerceEntitlement?] = []
    var purchaseEntitlement: CommerceEntitlement?
    var restoreEntitlement: CommerceEntitlement?
    var offeringsError: Error?
    var entitlementError: Error?
    var purchaseError: Error?
    var restoreError: Error?
    var configureCallCount = 0
    var loadOfferingCallCount = 0
    var refreshEntitlementCallCount = 0
    var purchaseDelayNanoseconds: UInt64?
    var restoreDelayNanoseconds: UInt64?

    func configureIfNeeded() {
        configureCallCount += 1
    }

    func loadOffering() async throws -> CommerceOffering? {
        loadOfferingCallCount += 1

        if let offeringsError {
            throw offeringsError
        }

        return currentOffering
    }

    func refreshEntitlement() async throws -> CommerceEntitlement? {
        refreshEntitlementCallCount += 1

        if let entitlementError {
            throw entitlementError
        }

        if !fetchedEntitlements.isEmpty {
            return fetchedEntitlements.removeFirst()
        }

        return fetchedEntitlement
    }

    func purchase(_ plan: CommercePlan) async throws -> CommerceEntitlement? {
        if let purchaseDelayNanoseconds {
            try? await Task.sleep(nanoseconds: purchaseDelayNanoseconds)
        }

        if let purchaseError {
            throw purchaseError
        }

        return purchaseEntitlement
    }

    func restorePurchases() async throws -> CommerceEntitlement? {
        if let restoreDelayNanoseconds {
            try? await Task.sleep(nanoseconds: restoreDelayNanoseconds)
        }

        if let restoreError {
            throw restoreError
        }

        return restoreEntitlement
    }
}

extension CommerceEntitlement {
    init(
        plan: CommercePlan,
        expirationDate: Date?,
        willRenew: Bool = false,
        originalPurchaseDate: Date? = nil
    ) {
        self.init(
            plan: plan,
            productIdentifier: "test.\(plan.rawValue)",
            entitlementIdentifier: "pro",
            expirationDate: expirationDate,
            willRenew: willRenew,
            originalPurchaseDate: originalPurchaseDate
        )
    }
}
