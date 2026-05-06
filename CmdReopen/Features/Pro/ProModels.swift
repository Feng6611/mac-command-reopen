//
//  ProModels.swift
//  CmdReopen
//
//  Created by Codex on 2026/4/26.
//

import Foundation
import RevenueCatCommerceKit

enum ProStatus: Equatable {
    case trial(daysRemaining: Int, expiresAt: Date)
    case expired
    case pro(plan: CommercePlan, expirationDate: Date?, willRenew: Bool)

    var isActive: Bool {
        switch self {
        case .trial, .pro:
            true
        case .expired:
            false
        }
    }

    var isPro: Bool {
        if case .pro = self {
            return true
        }

        return false
    }

    var isTrial: Bool {
        if case .trial = self {
            return true
        }

        return false
    }

    var renewalState: ProRenewalState? {
        renewalState(now: Date())
    }

    func renewalState(now: Date) -> ProRenewalState? {
        guard case .pro(let plan, let expirationDate, let willRenew) = self,
              plan == .yearly,
              let expirationDate else {
            return nil
        }

        let remaining = expirationDate.timeIntervalSince(now)
        let daysRemaining = remaining > 0 ? max(1, Int(ceil(remaining / 86_400))) : 0

        if willRenew {
            return .renews(on: expirationDate, daysRemaining: daysRemaining)
        }

        return .ends(on: expirationDate, daysRemaining: daysRemaining)
    }
}

enum ProRenewalState: Equatable {
    case renews(on: Date, daysRemaining: Int)
    case ends(on: Date, daysRemaining: Int)
}

struct ProPlanPackageMetadata: Equatable {
    let displayPrice: String
    let billingDetail: String
    let isAvailable: Bool
}

struct ProPlanProduct: Equatable, Identifiable {
    let plan: CommercePlan
    let title: String
    let displayPrice: String
    let billingDetail: String
    let subtitle: String
    let badge: String?
    let isAvailable: Bool

    var id: CommercePlan { plan }

    static func fallback(for plan: CommercePlan, isAvailable: Bool = true) -> Self {
        switch plan {
        case .yearly:
            return .init(
                plan: .yearly,
                title: String(localized: "Yearly"),
                displayPrice: "$5.99",
                billingDetail: String(localized: "per year"),
                subtitle: String(localized: "Auto-renews annually"),
                badge: nil,
                isAvailable: isAvailable
            )
        case .lifetime:
            return .init(
                plan: .lifetime,
                title: String(localized: "Lifetime"),
                displayPrice: "$10.99",
                billingDetail: String(localized: "once"),
                subtitle: String(localized: "Pay once, use forever"),
                badge: String(localized: "Best Value"),
                isAvailable: isAvailable
            )
        }
    }

    static let fallbackPlans: [Self] = [
        .fallback(for: .yearly),
        .fallback(for: .lifetime)
    ]
}
