//
//  RevenueCatService.swift
//  ComTab
//
//  Created by Codex on 2026/3/28.
//

import Foundation
import RevenueCat
import os

enum RevenueCatConfiguration {
    nonisolated static let apiKeyInfoKey = "ComTabRevenueCatAPIKey"
    nonisolated static var apiKey: String {
        let configuredKey = (Bundle.main.object(forInfoDictionaryKey: apiKeyInfoKey) as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let configuredKey, !configuredKey.isEmpty {
            return configuredKey
        }

        return ""
    }
    nonisolated static let entitlementIdentifier = "command reopen Pro"
    nonisolated static let offeringIdentifier = "default"
    nonisolated static let yearlyProductIdentifier = "com.dev.kkuk.CommandReopen.yearly"
    nonisolated static let lifetimeProductIdentifier = "com.dev.kkuk.CommandReopen.lifetime"
}

enum RevenueCatSnapshotParser {
    nonisolated static func resolveActiveEntitlement(from customerInfo: CustomerInfo, logger: Logger) -> EntitlementInfo? {
        let activeEntitlements = customerInfo.entitlements.all.values
            .filter(\.isActive)
            .sorted(by: Self.preferredEntitlementOrder)

        if let configuredEntitlement = customerInfo.entitlements.all[RevenueCatConfiguration.entitlementIdentifier] {
            if configuredEntitlement.isActive {
                return configuredEntitlement
            }
            logger.debug(
                "Entitlement id=\(RevenueCatConfiguration.entitlementIdentifier) present but inactive. product=\(configuredEntitlement.productIdentifier)"
            )
        }

        let fallbackEntitlement = activeEntitlements.first { entitlement in
            entitlement.productIdentifier == RevenueCatConfiguration.yearlyProductIdentifier
                || entitlement.productIdentifier == RevenueCatConfiguration.lifetimeProductIdentifier
        }

        if let fallbackEntitlement {
            logger.notice(
                "Falling back to active entitlement product=\(fallbackEntitlement.productIdentifier) because configured entitlement id=\(RevenueCatConfiguration.entitlementIdentifier) was not found or inactive."
            )
            return fallbackEntitlement
        }

        if let genericEntitlement = activeEntitlements.first {
            logger.notice(
                "Falling back to generic active entitlement id=\(genericEntitlement.identifier) product=\(genericEntitlement.productIdentifier) because configured entitlement id=\(RevenueCatConfiguration.entitlementIdentifier) was not found or inactive."
            )
            return genericEntitlement
        }

        return nil
    }

    private nonisolated static func preferredEntitlementOrder(_ lhs: EntitlementInfo, _ rhs: EntitlementInfo) -> Bool {
        switch (lhs.expirationDate, rhs.expirationDate) {
        case (.none, .some):
            return true
        case (.some, .none):
            return false
        case let (.some(lhsDate), .some(rhsDate)) where lhsDate != rhsDate:
            return lhsDate > rhsDate
        default:
            return lhs.identifier.localizedCompare(rhs.identifier) == .orderedAscending
        }
    }

    nonisolated static func makeEntitlementSnapshot(from customerInfo: CustomerInfo?) -> ProEntitlementSnapshot? {
        let logger = Logger(
            subsystem: Bundle.main.bundleIdentifier ?? "com.dev.kkuk.CmdReopen",
            category: "Purchase"
        )

        guard let customerInfo else {
            return nil
        }

        guard let entitlement = resolveActiveEntitlement(from: customerInfo, logger: logger) else {
            let activeEntitlementIdentifiers = customerInfo.entitlements.all
                .filter { $0.value.isActive }
                .map(\.key)
                .sorted()
                .joined(separator: ", ")
            let activeSubscriptionIdentifiers = Array(customerInfo.activeSubscriptions)
                .sorted()
                .joined(separator: ", ")

            if !activeEntitlementIdentifiers.isEmpty || !activeSubscriptionIdentifiers.isEmpty {
                logger.error(
                    "Expected entitlement id=\(RevenueCatConfiguration.entitlementIdentifier) not found. activeEntitlements=[\(activeEntitlementIdentifiers)] activeSubscriptions=[\(activeSubscriptionIdentifiers)]"
                )
            }
            return nil
        }

        let plan: ProPlan
        switch entitlement.productIdentifier {
        case RevenueCatConfiguration.lifetimeProductIdentifier:
            plan = .lifetime
        case RevenueCatConfiguration.yearlyProductIdentifier:
            plan = .yearly
        default:
            plan = entitlement.expirationDate == nil ? .lifetime : .yearly
        }

        logger.notice(
            "Mapped active entitlement id=\(RevenueCatConfiguration.entitlementIdentifier) product=\(entitlement.productIdentifier) plan=\(plan.rawValue)"
        )

        return ProEntitlementSnapshot(
            plan: plan,
            expirationDate: entitlement.expirationDate,
            willRenew: plan == .yearly && entitlement.willRenew,
            originalPurchaseDate: entitlement.originalPurchaseDate
        )
    }
}

extension ProPlan {
    var productIdentifier: String {
        switch self {
        case .yearly:
            RevenueCatConfiguration.yearlyProductIdentifier
        case .lifetime:
            RevenueCatConfiguration.lifetimeProductIdentifier
        }
    }
}

extension Offering {
    func package(for plan: ProPlan) -> Package? {
        switch plan {
        case .yearly:
            return self.annual
                ?? self.availablePackages.first(where: { $0.storeProduct.productIdentifier == plan.productIdentifier })
        case .lifetime:
            return self.lifetime
                ?? self.availablePackages.first(where: { $0.storeProduct.productIdentifier == plan.productIdentifier })
        }
    }
}

struct ProEntitlementSnapshot: Equatable, Sendable {
    let plan: ProPlan
    let expirationDate: Date?
    let willRenew: Bool
    let originalPurchaseDate: Date?

    nonisolated init(
        plan: ProPlan,
        expirationDate: Date?,
        willRenew: Bool = false,
        originalPurchaseDate: Date? = nil
    ) {
        self.plan = plan
        self.expirationDate = expirationDate
        self.willRenew = willRenew
        self.originalPurchaseDate = originalPurchaseDate
    }
}

@MainActor
protocol RevenueCatServicing: AnyObject {
    var cachedEntitlementSnapshot: ProEntitlementSnapshot? { get }
    var customerInfoDidChange: ((ProEntitlementSnapshot?) -> Void)? { get set }

    func configureIfNeeded()
    func fetchCurrentOffering() async throws -> Offering?
    func fetchEntitlementSnapshot() async throws -> ProEntitlementSnapshot?
    func purchase(plan: ProPlan, offering: Offering?) async throws -> ProEntitlementSnapshot?
    func restorePurchases() async throws -> ProEntitlementSnapshot?
}

@MainActor
final class RevenueCatService: NSObject, RevenueCatServicing {
    private enum Constants {
        static let requestTimeoutNanoseconds: UInt64 = 4_000_000_000
        static let invalidReceiptRecoveryDelayNanoseconds: UInt64 = 1_000_000_000
    }

    static let shared = RevenueCatService()

    var customerInfoDidChange: ((ProEntitlementSnapshot?) -> Void)?

    private(set) var isConfigured = false

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

    func fetchCurrentOffering() async throws -> Offering? {
        try ensureConfigured()

        let offerings = try await withTimeout("offerings") {
            try await Purchases.shared.offerings()
        }
        let resolvedOffering = offerings.current ?? offerings.all[RevenueCatConfiguration.offeringIdentifier]

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

        return resolvedOffering
    }

    func fetchEntitlementSnapshot() async throws -> ProEntitlementSnapshot? {
        try ensureConfigured()

        let customerInfo = try await withTimeout("customer info") {
            try await Purchases.shared.customerInfo(fetchPolicy: .fetchCurrent)
        }
        return RevenueCatSnapshotParser.makeEntitlementSnapshot(from: customerInfo)
    }

    func purchase(plan: ProPlan, offering: Offering?) async throws -> ProEntitlementSnapshot? {
        try ensureConfigured()

        let resolvedOffering = try await resolveOffering(offering)
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

    private func resolveOffering(_ offering: Offering?) async throws -> Offering {
        if let offering {
            return offering
        }

        if let fetched = try await fetchCurrentOffering() {
            return fetched
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
