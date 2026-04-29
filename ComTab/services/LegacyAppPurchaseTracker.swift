//
//  LegacyAppPurchaseTracker.swift
//  ComTab
//
//  Created by Codex on 2026/4/26.
//

import Foundation
import os
import StoreKit

struct LegacyAppPurchaseSnapshot: Equatable, Sendable {
    let originalAppVersion: String
    let originalPurchaseDate: Date?

    var asEntitlementSnapshot: ProEntitlementSnapshot {
        .init(
            plan: .lifetime,
            expirationDate: nil,
            willRenew: false,
            originalPurchaseDate: originalPurchaseDate
        )
    }
}

@MainActor
protocol LegacyAppPurchaseChecking: AnyObject {
    var cachedLegacyAppPurchaseSnapshot: LegacyAppPurchaseSnapshot? { get }

    func refreshLegacyAppPurchaseSnapshot() async -> LegacyAppPurchaseSnapshot?
}

@MainActor
final class LegacyAppPurchaseTracker: LegacyAppPurchaseChecking {
    static let shared = LegacyAppPurchaseTracker()

    private(set) var cachedLegacyAppPurchaseSnapshot: LegacyAppPurchaseSnapshot?

    func refreshLegacyAppPurchaseSnapshot() async -> LegacyAppPurchaseSnapshot? {
        do {
            let verificationResult = try await AppTransaction.shared
            let snapshot = Self.snapshotIfGrandfathered(from: verificationResult)
            cachedLegacyAppPurchaseSnapshot = snapshot
            logGrandfatheredSnapshotIfNeeded(snapshot)
            return snapshot
        } catch {
            AppLogger.purchase.error("Failed to load AppTransaction for grandfathering: \(error.localizedDescription)")
        }

        do {
            let snapshot = try Self.snapshotIfGrandfatheredFromLocalReceipt()
            cachedLegacyAppPurchaseSnapshot = snapshot
            logGrandfatheredSnapshotIfNeeded(snapshot)
            return snapshot
        } catch {
            AppLogger.purchase.error("Failed to parse App Store receipt for grandfathering: \(error.localizedDescription)")
            return cachedLegacyAppPurchaseSnapshot
        }
    }

    private func logGrandfatheredSnapshotIfNeeded(_ snapshot: LegacyAppPurchaseSnapshot?) {
        guard let snapshot else {
            return
        }

        let purchaseDateDescription = snapshot.originalPurchaseDate?.formatted() ?? "unknown"
        AppLogger.purchase.notice(
            "Detected grandfathered paid-app customer. originalVersion=\(snapshot.originalAppVersion) purchaseDate=\(purchaseDateDescription)"
        )
    }

    private static func snapshotIfGrandfathered(
        from verificationResult: StoreKit.VerificationResult<StoreKit.AppTransaction>
    ) -> LegacyAppPurchaseSnapshot? {
        guard case .verified(let transaction) = verificationResult else {
            AppLogger.purchase.error("AppTransaction verification failed; skipping grandfathering.")
            return nil
        }

        guard isGrandfathered(originalAppVersion: transaction.originalAppVersion) else {
            return nil
        }

        return LegacyAppPurchaseSnapshot(
            originalAppVersion: transaction.originalAppVersion,
            originalPurchaseDate: transaction.originalPurchaseDate
        )
    }

    private static func isGrandfathered(originalAppVersion: String) -> Bool {
        originalAppVersion.compare(ProStatusManager.Constants.grandfatheringCutoffVersion, options: .numeric) == .orderedAscending
    }

    private static func snapshotIfGrandfatheredFromLocalReceipt() throws -> LegacyAppPurchaseSnapshot? {
        guard let receiptURL = Bundle.main.appStoreReceiptURL else {
            return nil
        }

        let receiptData = try Data(contentsOf: receiptURL)
        let payloadData = try LegacyAppStoreReceiptParser.extractPayload(fromSignedReceiptData: receiptData)
        let receipt = try LegacyAppStoreReceiptParser.parse(payloadData: payloadData)

        guard isGrandfathered(originalAppVersion: receipt.originalAppVersion) else {
            return nil
        }

        return LegacyAppPurchaseSnapshot(
            originalAppVersion: receipt.originalAppVersion,
            originalPurchaseDate: nil
        )
    }
}
