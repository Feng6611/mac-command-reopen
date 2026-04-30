//
//  RevenueCatService.swift
//  ComTab
//
//  Created by Codex on 2026/3/28.
//

import Foundation
import RevenueCatCommerceKit
import os

@MainActor
final class RevenueCatService: RevenueCatServicing {
    static let shared = RevenueCatService()

    var customerInfoDidChange: ((ProEntitlementSnapshot?) -> Void)? {
        didSet {
            bindCustomerInfoDidChange()
        }
    }

    private let commerceClient: any CommerceClient

    var cachedEntitlementSnapshot: ProEntitlementSnapshot? {
        commerceClient.cachedEntitlement?.proEntitlementSnapshot
    }

    init(commerceClient: (any CommerceClient)? = nil) {
        self.commerceClient = commerceClient ?? RevenueCatCommerceClient(
            configuration: RevenueCatConfiguration.commerceConfiguration
        )
        bindCustomerInfoDidChange()
    }

    func configureIfNeeded() {
        commerceClient.configureIfNeeded()
    }

    func fetchEntitlementSnapshot() async throws -> ProEntitlementSnapshot? {
        try await commerceClient.refreshEntitlement()?.proEntitlementSnapshot
    }

    func fetchCurrentOffering() async throws -> ProOfferingSnapshot? {
        try await commerceClient.loadOffering()?.proOfferingSnapshot
    }

    func purchase(plan: ProPlan) async throws -> ProEntitlementSnapshot? {
        try await commerceClient.purchase(plan.commercePlan)?.proEntitlementSnapshot
    }

    func restorePurchases() async throws -> ProEntitlementSnapshot? {
        try await commerceClient.restorePurchases()?.proEntitlementSnapshot
    }

    private func bindCustomerInfoDidChange() {
        commerceClient.entitlementDidChange = { [weak self] entitlement in
            guard let self else {
                return
            }

            self.customerInfoDidChange?(entitlement?.proEntitlementSnapshot)
        }
    }
}

@MainActor
protocol RevenueCatServicing: AnyObject {
    var cachedEntitlementSnapshot: ProEntitlementSnapshot? { get }
    var customerInfoDidChange: ((ProEntitlementSnapshot?) -> Void)? { get set }

    func configureIfNeeded()
    func fetchCurrentOffering() async throws -> ProOfferingSnapshot?
    func fetchEntitlementSnapshot() async throws -> ProEntitlementSnapshot?
    func purchase(plan: ProPlan) async throws -> ProEntitlementSnapshot?
    func restorePurchases() async throws -> ProEntitlementSnapshot?
}
