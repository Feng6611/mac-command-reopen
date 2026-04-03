//
//  CommerceStateSource.swift
//  ComTab
//
//  Created by Codex on 2026/3/29.
//

import Combine
import Foundation

enum AccessEntitlementState: Equatable {
    case unrestricted
    case trial
    case expired
    case pro

    var isCoreFeatureAvailable: Bool {
        switch self {
        case .unrestricted, .trial, .pro:
            true
        case .expired:
            false
        }
    }

    var showsUpgradeEntry: Bool {
        switch self {
        case .trial, .expired:
            true
        case .unrestricted, .pro:
            false
        }
    }
}

@MainActor
protocol CommerceStateSource: AnyObject {
    var entitlementState: AccessEntitlementState { get }
    var isFirstLaunch: Bool { get }
    var shouldOpenProSettings: Bool { get }
    var entitlementStatePublisher: AnyPublisher<AccessEntitlementState, Never> { get }
    var proSettingsPromptPublisher: AnyPublisher<Bool, Never> { get }

    func configureIfNeeded()
    func refresh() async
    func markPromptHandled()
}
