//
//  ProPurchaseError.swift
//  ComTab
//
//  Created by Codex on 2026/4/26.
//

import Foundation
import RevenueCat

enum ProPurchaseError: Error, Equatable {
    case notConfigured
    case offeringUnavailable
    case packageNotFound(ProPlan)
    case purchaseCancelled
    case purchaseNotAllowed
    case activationPending
    case invalidReceipt
    case network
    case invalidCredentials
    case productUnavailable
    case unknown(String)

    init(error: Error) {
        if let purchaseError = error as? ProPurchaseError {
            self = purchaseError
            return
        }

        let nsError = error as NSError
        if nsError.domain == RevenueCat.ErrorCode.errorDomain,
           let errorCode = RevenueCat.ErrorCode(rawValue: nsError.code) {
            switch errorCode {
            case .purchaseCancelledError:
                self = .purchaseCancelled
            case .purchaseNotAllowedError:
                self = .purchaseNotAllowed
            case .invalidReceiptError:
                self = .invalidReceipt
            case .productNotAvailableForPurchaseError:
                self = .productUnavailable
            case .networkError:
                self = .network
            case .invalidCredentialsError:
                self = .invalidCredentials
            case .configurationError:
                self = .notConfigured
            default:
                self = .unknown(nsError.localizedDescription)
            }
        } else {
            self = .unknown(nsError.localizedDescription)
        }
    }
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
