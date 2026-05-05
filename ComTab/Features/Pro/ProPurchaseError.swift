//
//  ProPurchaseError.swift
//  ComTab
//
//  Created by Codex on 2026/4/26.
//

import Foundation
import RevenueCatCommerceKit

enum ProPurchaseError: Error, Equatable {
    case notConfigured
    case offeringUnavailable
    case packageNotFound(CommercePlan)
    case purchaseCancelled
    case purchaseNotAllowed
    case activationPending
    case invalidReceipt
    case network
    case invalidCredentials
    case productUnavailable
    case unknown(String)
}

extension ProPurchaseError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .notConfigured:
            "Purchases are not configured yet."
        case .offeringUnavailable:
            "No products are currently available."
        case .packageNotFound(let plan):
            "The \(plan.rawValue) product is not available in the current offering."
        case .purchaseCancelled:
            "The purchase was cancelled."
        case .purchaseNotAllowed:
            "Purchases are not allowed on this Mac."
        case .activationPending:
            "Purchase completed, but Pro access is still syncing. Please wait a moment or use Restore Purchase."
        case .invalidReceipt:
            "The App Store did not finish syncing this purchase yet. Please try again in a moment or use Restore Purchase."
        case .network:
            "A network connection is required to load purchases."
        case .invalidCredentials:
            "The RevenueCat API key is invalid."
        case .productUnavailable:
            "This product is not available for purchase."
        case .unknown(let message):
            message
        }
    }
}

extension ProPurchaseError {
    init(error: Error) {
        if let purchaseError = error as? ProPurchaseError {
            self = purchaseError
            return
        }

        if let commerceError = error as? CommercePurchaseError {
            self = ProPurchaseError(commerceError: commerceError)
            return
        }

        let nsError = error as NSError
        self = .unknown(nsError.localizedDescription)
    }

    private init(commerceError: CommercePurchaseError) {
        switch commerceError {
        case .notConfigured, .invalidConfiguration:
            self = .notConfigured
        case .offeringUnavailable:
            self = .offeringUnavailable
        case .packageNotFound(let plan), .productIdentifierMissing(let plan):
            self = .packageNotFound(plan)
        case .purchaseCancelled:
            self = .purchaseCancelled
        case .purchaseNotAllowed:
            self = .purchaseNotAllowed
        case .activationPending:
            self = .activationPending
        case .invalidReceipt:
            self = .invalidReceipt
        case .network:
            self = .network
        case .invalidCredentials:
            self = .invalidCredentials
        case .productUnavailable:
            self = .productUnavailable
        case .unknown(let message):
            self = .unknown(message)
        }
    }
}
