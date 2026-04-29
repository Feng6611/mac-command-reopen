//
//  ProStatus.swift
//  ComTab
//
//  Created by Codex on 2026/4/26.
//

import Foundation

enum ProStatus: Equatable {
    case trial(daysRemaining: Int, expiresAt: Date)
    case expired
    case pro(plan: ProPlan, expirationDate: Date?, willRenew: Bool)

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
