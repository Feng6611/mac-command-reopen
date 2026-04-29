//
//  RevenueCatService.swift
//  ComTab
//
//  Created by Codex on 2026/3/28.
//

import Foundation
import RevenueCat
import os

@MainActor
final class RevenueCatService: NSObject, RevenueCatServicing {
    private enum Constants {
        static let requestTimeoutNanoseconds: UInt64 = 4_000_000_000
        static let invalidReceiptRecoveryDelayNanoseconds: UInt64 = 1_000_000_000
    }

    static let shared = RevenueCatService()

    var customerInfoDidChange: ((ProEntitlementSnapshot?) -> Void)?

    private(set) var isConfigured = false
    private var currentOffering: Offering?

    var cachedEntitlementSnapshot: ProEntitlementSnapshot? {
        guard isConfigured else {
            return nil
        }

        return RevenueCatSnapshotParser.makeEntitlementSnapshot(from: Purchases.shared.cachedCustomerInfo)
    }

    func configureIfNeeded() {
        guard !isConfigured else {
            return
        }

        guard !RevenueCatConfiguration.apiKey.isEmpty else {
            AppLogger.purchase.error("RevenueCat configuration skipped because \(RevenueCatConfiguration.apiKeyInfoKey) is missing.")
            return
        }

#if !DEBUG
        guard !RevenueCatConfiguration.apiKey.hasPrefix("test_") else {
            AppLogger.purchase.error("Skipping RevenueCat configuration in non-debug build because the API key is a test key.")
            return
        }
#endif

#if DEBUG
        Purchases.logLevel = .debug
#else
        Purchases.logLevel = .warn
#endif

        let configuration = Configuration
            .builder(withAPIKey: RevenueCatConfiguration.apiKey)
            .with(storeKitVersion: .storeKit2)
            // RevenueCat 5.67.0 still marks `.enforced` unavailable, so keep the strongest
            // public verification mode that this SDK release supports.
            .with(entitlementVerificationMode: .informational)
            .with(showStoreMessagesAutomatically: true)
            .build()

        Purchases.configure(with: configuration)
        Purchases.shared.delegate = self
        isConfigured = true

        AppLogger.purchase.notice("RevenueCat configured.")
    }

    func fetchCurrentOffering() async throws -> ProOfferingSnapshot? {
        try ensureConfigured()

        let offerings = try await withTimeout("offerings") {
            try await Purchases.shared.offerings()
        }
        let resolvedOffering = offerings.current ?? offerings.all[RevenueCatConfiguration.offeringIdentifier]
        currentOffering = resolvedOffering

        if let resolvedOffering {
            let packageIdentifiers = resolvedOffering.availablePackages.map(\.identifier).joined(separator: ", ")
            AppLogger.purchase.notice(
                "Loaded RevenueCat offering id=\(resolvedOffering.identifier) packages=[\(packageIdentifiers)]"
            )
        } else {
            AppLogger.purchase.error(
                "RevenueCat returned no current/default offering. current=\(String(describing: offerings.current?.identifier))"
            )
        }

        return resolvedOffering?.proOfferingSnapshot()
    }

    func fetchEntitlementSnapshot() async throws -> ProEntitlementSnapshot? {
        try ensureConfigured()

        let customerInfo = try await withTimeout("customer info") {
            try await Purchases.shared.customerInfo(fetchPolicy: .fetchCurrent)
        }
        return RevenueCatSnapshotParser.makeEntitlementSnapshot(from: customerInfo)
    }

    func purchase(plan: ProPlan) async throws -> ProEntitlementSnapshot? {
        try ensureConfigured()

        let resolvedOffering = try await resolveOffering()
        guard let package = resolvedOffering.package(for: plan) else {
            throw ProPurchaseError.packageNotFound(plan)
        }
        AppLogger.purchase.notice(
            "Starting purchase. plan=\(plan.rawValue) package=\(package.identifier) product=\(package.storeProduct.productIdentifier)"
        )

        do {
            let result = try await Purchases.shared.purchase(package: package)
            if result.userCancelled {
                throw ProPurchaseError.purchaseCancelled
            }

            return RevenueCatSnapshotParser.makeEntitlementSnapshot(from: result.customerInfo)
        } catch {
            if isInvalidReceiptError(error) {
                AppLogger.purchase.error(
                    "Purchase returned an invalid receipt for plan=\(plan.rawValue). Attempting entitlement recovery."
                )

                if let recoveredSnapshot = try await recoverSnapshotAfterInvalidReceipt() {
                    AppLogger.purchase.notice("Recovered purchase after invalid receipt for plan=\(plan.rawValue).")
                    return recoveredSnapshot
                }
            }

            throw error
        }
    }

    func restorePurchases() async throws -> ProEntitlementSnapshot? {
        try ensureConfigured()

        let customerInfo = try await withTimeout("restore purchases") {
            try await Purchases.shared.restorePurchases()
        }
        return RevenueCatSnapshotParser.makeEntitlementSnapshot(from: customerInfo)
    }

    private func ensureConfigured() throws {
        guard isConfigured else {
            throw ProPurchaseError.notConfigured
        }
    }

    private func resolveOffering() async throws -> Offering {
        if let currentOffering {
            return currentOffering
        }

        _ = try await fetchCurrentOffering()
        if let currentOffering {
            return currentOffering
        }

        throw ProPurchaseError.offeringUnavailable
    }

    private func recoverSnapshotAfterInvalidReceipt() async throws -> ProEntitlementSnapshot? {
        try? await Task.sleep(nanoseconds: Constants.invalidReceiptRecoveryDelayNanoseconds)

        if let refreshedSnapshot = try await fetchEntitlementSnapshot() {
            return refreshedSnapshot
        }

        return try await restorePurchases()
    }

    private func isInvalidReceiptError(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == RevenueCat.ErrorCode.errorDomain
            && RevenueCat.ErrorCode(rawValue: nsError.code) == .invalidReceiptError
    }

    private func withTimeout<T>(
        _ operationName: String,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }

            group.addTask {
                try await Task.sleep(nanoseconds: Constants.requestTimeoutNanoseconds)
                throw ProPurchaseError.network
            }

            defer { group.cancelAll() }

            guard let result = try await group.next() else {
                AppLogger.purchase.error("Timed out waiting for \(operationName) with no result.")
                throw ProPurchaseError.network
            }

            return result
        }
    }
}

extension RevenueCatService: PurchasesDelegate {
    nonisolated func purchases(_ purchases: Purchases, receivedUpdated customerInfo: CustomerInfo) {
        let snapshot = RevenueCatSnapshotParser.makeEntitlementSnapshot(from: customerInfo)

        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            self.customerInfoDidChange?(snapshot)
        }
    }
}
