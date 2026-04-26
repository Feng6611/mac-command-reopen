//
//  ProPlans.swift
//  ComTab
//
//  Created by Codex on 2026/4/26.
//

import Foundation

enum ProPlan: String, Equatable, Sendable {
    case yearly
    case lifetime
}

struct ProPlanPackageMetadata: Equatable {
    let displayPrice: String
    let billingDetail: String
    let isAvailable: Bool
}

struct ProPlanProduct: Equatable, Identifiable {
    let plan: ProPlan
    let title: String
    let displayPrice: String
    let billingDetail: String
    let subtitle: String
    let badge: String?
    let isAvailable: Bool

    var id: ProPlan { plan }

    static func fallback(for plan: ProPlan, isAvailable: Bool = true) -> Self {
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
