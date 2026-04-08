//
//  AppAccessController.swift
//  ComTab
//
//  Created by Codex on 2026/3/29.
//

import Combine
import Foundation

@MainActor
protocol FeatureAvailabilityProviding: AnyObject {
    var isCoreFeatureAvailable: Bool { get }
}

@MainActor
final class AppAccessController: ObservableObject, FeatureAvailabilityProviding {
    static let shared = AppAccessController.makeShared()

    @Published private(set) var entitlementState: AccessEntitlementState
    @Published private(set) var shouldOpenProSettings = false

    let distributionChannel: DistributionChannel

    private let commerceStateSource: CommerceStateSource?
    private var cancellables: Set<AnyCancellable> = []

    var isCoreFeatureAvailable: Bool {
        entitlementState.isCoreFeatureAvailable
    }

    var showsProTab: Bool {
        true
    }

    var showsUpgradeEntry: Bool {
        distributionChannel == .appStore && entitlementState.showsUpgradeEntry
    }

    var shouldShowOnboarding: Bool {
        distributionChannel == .appStore
            && (commerceStateSource?.isFirstLaunch ?? false)
    }

    init(
        distributionChannel: DistributionChannel = .current,
        commerceStateSource: CommerceStateSource? = nil
    ) {
        self.distributionChannel = distributionChannel
        self.commerceStateSource = commerceStateSource
        self.entitlementState = commerceStateSource?.entitlementState ?? .unrestricted
        self.shouldOpenProSettings = commerceStateSource?.shouldOpenProSettings ?? false
        bindIfNeeded()
    }

    func configureIfNeeded() {
        commerceStateSource?.configureIfNeeded()
        syncFromSource()
    }

    func refresh() async {
        await commerceStateSource?.refresh()
        syncFromSource()
    }

    func markPromptHandled() {
        commerceStateSource?.markPromptHandled()
        shouldOpenProSettings = false
    }

    private func bindIfNeeded() {
        commerceStateSource?.entitlementStatePublisher
            .sink { [weak self] state in
                self?.entitlementState = state
            }
            .store(in: &cancellables)

        commerceStateSource?.proSettingsPromptPublisher
            .sink { [weak self] shouldOpen in
                self?.shouldOpenProSettings = shouldOpen
            }
            .store(in: &cancellables)
    }

    private func syncFromSource() {
        entitlementState = commerceStateSource?.entitlementState ?? .unrestricted
        shouldOpenProSettings = commerceStateSource?.shouldOpenProSettings ?? false
    }

    private static func makeShared() -> AppAccessController {
        switch DistributionChannel.current {
        case .direct:
            AppAccessController(distributionChannel: .direct)
        case .appStore:
#if APPSTORE
            AppAccessController(
                distributionChannel: .appStore,
                commerceStateSource: ProCommerceStateSource.shared
            )
#else
            AppAccessController(distributionChannel: .appStore)
#endif
        }
    }
}
