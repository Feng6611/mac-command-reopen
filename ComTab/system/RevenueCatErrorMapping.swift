//
//  RevenueCatErrorMapping.swift
//  ComTab
//
//  Created by Codex on 2026/4/29.
//

import Foundation
import RevenueCatCommerceKit

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
            self = .packageNotFound(plan.proPlan)
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
