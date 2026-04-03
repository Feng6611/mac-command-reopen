//
//  ProCommerceStateSource.swift
//  ComTab
//
//  Created by Codex on 2026/3/29.
//

import Combine
import Foundation

@MainActor
final class ProCommerceStateSource: CommerceStateSource {
    static let shared = ProCommerceStateSource(proStatusManager: .shared)

    private let proStatusManager: ProStatusManager

    init(proStatusManager: ProStatusManager) {
        self.proStatusManager = proStatusManager
    }

    var entitlementState: AccessEntitlementState {
        proStatusManager.accessEntitlementState
    }

    var isFirstLaunch: Bool {
        proStatusManager.isFirstLaunch
    }

    var shouldOpenProSettings: Bool {
        proStatusManager.shouldOpenProSettings
    }

    var entitlementStatePublisher: AnyPublisher<AccessEntitlementState, Never> {
        Publishers.CombineLatest(proStatusManager.$status, proStatusManager.$lastError)
            .map { [self] _, _ in
                proStatusManager.accessEntitlementState
            }
            .eraseToAnyPublisher()
    }

    var proSettingsPromptPublisher: AnyPublisher<Bool, Never> {
        proStatusManager.$shouldOpenProSettings
            .eraseToAnyPublisher()
    }

    func configureIfNeeded() {
        proStatusManager.configureIfNeeded()
    }

    func refresh() async {
        await proStatusManager.refresh()
    }

    func markPromptHandled() {
        proStatusManager.markExpiredPromptHandled()
    }
}
