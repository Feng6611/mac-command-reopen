//
//  ProPurchaseError.swift
//  CmdReopen
//
//  Created by Codex on 2026/4/26.
//

import Foundation
import KikiCommerceCore

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
    /// These are read by someone trying to pay, so each one says what is wrong
    /// in their terms and what they can do next. Cases the user cannot act on
    /// — a missing or rejected API key, a plan absent from the offering — name
    /// the situation rather than our configuration, and never expose the
    /// commerce vendor or a raw plan identifier.
    var errorDescription: String? {
        MainActor.assumeIsolated {
            switch self {
        case .notConfigured, .invalidCredentials:
            AppLanguage.shared.string(
                localized: "Purchases aren’t available in this build. Please contact support.",
                comment: "Shown when the app's commerce configuration is missing or rejected; the user cannot fix this."
            )
        case .offeringUnavailable, .packageNotFound, .productUnavailable:
            AppLanguage.shared.string(
                localized: "The App Store isn’t offering this plan right now. Try again later.",
                comment: "Shown when the store returns no purchasable product for a plan."
            )
        case .purchaseCancelled:
            AppLanguage.shared.string("The purchase was cancelled.")
        case .purchaseNotAllowed:
            AppLanguage.shared.string(
                localized: "Purchases are turned off on this Mac. Check your Screen Time content and privacy restrictions.",
                comment: "StoreKit reports payments are not allowed, which on macOS is a Screen Time restriction."
            )
        case .activationPending:
            AppLanguage.shared.string(localized: "Purchase completed, but Pro access is still syncing. Please wait a moment or use Restore Purchase.", comment: "Purchase-sync error; 'Restore Purchase' is a button title and must match its translation.")
        case .invalidReceipt:
            AppLanguage.shared.string(localized: "The App Store did not finish syncing this purchase yet. Please try again in a moment or use Restore Purchase.", comment: "Purchase-sync error; 'Restore Purchase' is a button title and must match its translation.")
        case .network:
            AppLanguage.shared.string(
                localized: "No internet connection. Connect and try again to load purchases.",
                comment: "Shown when the store cannot be reached."
            )
        case .unknown(let message):
            message
            }
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

    init(commerceError: CommercePurchaseError) {
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
