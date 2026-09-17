//
//  ProCommerceStateSource.swift
//  CmdReopen
//
//  Created by Codex on 2026/3/29.
//

import Combine
import Foundation
import KikiCommerceCore

@MainActor
final class ProCommerceStateSource: CommerceStateSource {
    static var shared: ProCommerceStateSource { AppComposition.shared.commerceSource }

    private let proStatusManager: CommandAccessModel

    init(proStatusManager: CommandAccessModel) {
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

    var hasResolvedInitialRefresh: Bool {
        proStatusManager.readiness.hasResolvedInitialRefresh
    }

    var allowsAutomaticPresentation: Bool {
        proStatusManager.readiness.allowsAutomaticPresentation
    }

    var entitlementStatePublisher: AnyPublisher<AccessEntitlementState, Never> {
        Publishers.CombineLatest(
            proStatusManager.accessManager.$status,
            proStatusManager.accessManager.$readiness
        )
            .map { status, readiness in
                // Published emits before its stored property changes.
                CommandAccessModel.entitlementState(status: status, readiness: readiness)
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
