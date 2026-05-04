import Foundation
import RevenueCat
import os

@MainActor
public final class RevenueCatCommerceClient: NSObject, CommerceClient {
    public var entitlementDidChange: ((CommerceEntitlement?) -> Void)?

    public private(set) var isConfigured = false

    private let configuration: CommerceConfiguration
    private let logger: Logger
    private let sdkClient: any RevenueCatSDKClient
    private var currentOffering: Offering?

    public init(configuration: CommerceConfiguration) {
        self.configuration = configuration
        self.sdkClient = RevenueCatPurchasesSDKClient()
        self.logger = Logger(
            subsystem: configuration.logSubsystem,
            category: configuration.logCategory
        )
        super.init()
        bindSDKClient()
    }

    init(configuration: CommerceConfiguration, sdkClient: any RevenueCatSDKClient) {
        self.configuration = configuration
        self.sdkClient = sdkClient
        self.logger = Logger(
            subsystem: configuration.logSubsystem,
            category: configuration.logCategory
        )
        super.init()
        bindSDKClient()
    }

    public var cachedEntitlement: CommerceEntitlement? {
        guard isConfigured else {
            return nil
        }

        return RevenueCatSnapshotMapper.makeEntitlement(
            from: sdkClient.cachedCustomerInfo,
            configuration: configuration,
            logger: logger
        )
    }

    public func configureIfNeeded() {
        guard !isConfigured else {
            return
        }

        guard !configuration.apiKey.isEmpty else {
            logger.error("RevenueCat configuration skipped because the API key is missing.")
            return
        }

#if !DEBUG
        guard configuration.allowsTestAPIKeyInRelease || !configuration.apiKey.hasPrefix("test_") else {
            logger.error("Skipping RevenueCat configuration in non-debug build because the API key is a test key.")
            return
        }
#endif

        sdkClient.configure(with: configuration)
        isConfigured = true

        logger.notice("RevenueCat configured.")
    }

    public func loadOffering() async throws -> CommerceOffering? {
        try ensureConfigured()

        let offerings = try await withTimeout("offerings") {
            try await self.sdkClient.offerings()
        }
        let resolvedOffering = resolveOffering(from: offerings)
        currentOffering = resolvedOffering

        guard let resolvedOffering else {
            logger.error("RevenueCat returned no usable current/configured offering.")
            return nil
        }

        let packageIdentifiers = resolvedOffering.availablePackages.map(\.identifier).joined(separator: ", ")
        logger.notice("Loaded RevenueCat offering id=\(resolvedOffering.identifier) packages=[\(packageIdentifiers)]")

        return RevenueCatSnapshotMapper.makeOffering(
            from: resolvedOffering,
            configuration: configuration
        )
    }

    public func refreshEntitlement() async throws -> CommerceEntitlement? {
        try ensureConfigured()

        let customerInfo = try await withTimeout("customer info") {
            try await self.sdkClient.customerInfo(fetchPolicy: .fetchCurrent)
        }

        return RevenueCatSnapshotMapper.makeEntitlement(
            from: customerInfo,
            configuration: configuration,
            logger: logger
        )
    }

    public func purchase(_ plan: CommercePlan) async throws -> CommerceEntitlement? {
        try ensureConfigured()

        let resolvedOffering = try await resolveOffering()
        guard let package = resolvedOffering.package(for: plan, configuration: configuration) else {
            throw CommercePurchaseError.packageNotFound(plan)
        }

        logger.notice(
            "Starting purchase. plan=\(plan.rawValue) package=\(package.identifier) product=\(package.storeProduct.productIdentifier)"
        )

        do {
            let result = try await sdkClient.purchase(package: package)
            if result.userCancelled {
                throw CommercePurchaseError.purchaseCancelled
            }

            return RevenueCatSnapshotMapper.makeEntitlement(
                from: result.customerInfo,
                configuration: configuration,
                logger: logger
            )
        } catch {
            if isInvalidReceiptError(error) {
                logger.error("Purchase returned an invalid receipt for plan=\(plan.rawValue). Attempting entitlement recovery.")

                do {
                    if let recoveredEntitlement = try await recoverEntitlementAfterInvalidReceipt() {
                        logger.notice("Recovered purchase after invalid receipt for plan=\(plan.rawValue).")
                        return recoveredEntitlement
                    }
                } catch {
                    throw CommercePurchaseError(error: error)
                }
            }

            throw CommercePurchaseError(error: error)
        }
    }

    public func restorePurchases() async throws -> CommerceEntitlement? {
        try ensureConfigured()

        let customerInfo = try await withTimeout("restore purchases") {
            try await self.sdkClient.restorePurchases()
        }

        return RevenueCatSnapshotMapper.makeEntitlement(
            from: customerInfo,
            configuration: configuration,
            logger: logger
        )
    }

    private func ensureConfigured() throws {
        guard isConfigured else {
            throw CommercePurchaseError.notConfigured
        }
    }

    private func bindSDKClient() {
        sdkClient.customerInfoDidChange = { [weak self] customerInfo in
            guard let self else {
                return
            }

            let entitlement = RevenueCatSnapshotMapper.makeEntitlement(
                from: customerInfo,
                configuration: self.configuration,
                logger: self.logger
            )
            self.entitlementDidChange?(entitlement)
        }
    }

    private func resolveOffering() async throws -> Offering {
        if let currentOffering {
            return currentOffering
        }

        _ = try await loadOffering()
        if let currentOffering {
            return currentOffering
        }

        throw CommercePurchaseError.offeringUnavailable
    }

    private func resolveOffering(from offerings: RevenueCatSDKOfferings) -> Offering? {
        let current = offerings.current
        if let current, current.hasConfiguredProducts(configuration: configuration) {
            return current
        }

        let configured = offerings.all[configuration.offeringIdentifier]
        if let configured, configured.hasConfiguredProducts(configuration: configuration) {
            if let current {
                logger.notice(
                    "Current RevenueCat offering id=\(current.identifier) has no configured products. Falling back to configured offering id=\(configured.identifier)."
                )
            }
            return configured
        }

        return current ?? configured
    }

    private func recoverEntitlementAfterInvalidReceipt() async throws -> CommerceEntitlement? {
        try? await Task.sleep(nanoseconds: configuration.invalidReceiptRecoveryDelayNanoseconds)

        if let refreshedEntitlement = try await refreshEntitlement() {
            return refreshedEntitlement
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

            group.addTask { [configuration] in
                try await Task.sleep(nanoseconds: configuration.requestTimeoutNanoseconds)
                throw CommercePurchaseError.network
            }

            defer { group.cancelAll() }

            guard let result = try await group.next() else {
                logger.error("Timed out waiting for \(operationName) with no result.")
                throw CommercePurchaseError.network
            }

            return result
        }
    }
}

protocol RevenueCatSDKClient: AnyObject {
    var cachedCustomerInfo: CustomerInfo? { get }
    var customerInfoDidChange: ((CustomerInfo) -> Void)? { get set }

    func configure(with configuration: CommerceConfiguration)
    func offerings() async throws -> RevenueCatSDKOfferings
    func customerInfo(fetchPolicy: CacheFetchPolicy) async throws -> CustomerInfo
    func purchase(package: Package) async throws -> PurchaseResultData
    func restorePurchases() async throws -> CustomerInfo
}

struct RevenueCatSDKOfferings: Sendable {
    let current: Offering?
    let all: [String: Offering]
}

final class RevenueCatPurchasesSDKClient: NSObject, RevenueCatSDKClient {
    var customerInfoDidChange: ((CustomerInfo) -> Void)?

    var cachedCustomerInfo: CustomerInfo? {
        Purchases.shared.cachedCustomerInfo
    }

    func configure(with configuration: CommerceConfiguration) {
#if DEBUG
        Purchases.logLevel = .debug
#else
        Purchases.logLevel = .warn
#endif

        let revenueCatConfiguration = Configuration
            .builder(withAPIKey: configuration.apiKey)
            .with(storeKitVersion: .storeKit2)
            .with(entitlementVerificationMode: .informational)
            .with(showStoreMessagesAutomatically: configuration.showStoreMessagesAutomatically)
            .build()

        Purchases.configure(with: revenueCatConfiguration)
        Purchases.shared.delegate = self
    }

    func offerings() async throws -> RevenueCatSDKOfferings {
        let offerings = try await Purchases.shared.offerings()
        return RevenueCatSDKOfferings(current: offerings.current, all: offerings.all)
    }

    func customerInfo(fetchPolicy: CacheFetchPolicy) async throws -> CustomerInfo {
        try await Purchases.shared.customerInfo(fetchPolicy: fetchPolicy)
    }

    func purchase(package: Package) async throws -> PurchaseResultData {
        try await Purchases.shared.purchase(package: package)
    }

    func restorePurchases() async throws -> CustomerInfo {
        try await Purchases.shared.restorePurchases()
    }
}

extension RevenueCatPurchasesSDKClient: PurchasesDelegate {
    nonisolated func purchases(_ purchases: Purchases, receivedUpdated customerInfo: CustomerInfo) {
        Task { @MainActor [weak self] in
            self?.customerInfoDidChange?(customerInfo)
        }
    }
}
