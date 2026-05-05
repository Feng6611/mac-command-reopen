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

    private let commerceStateSourceFactory: (() -> CommerceStateSource?)?
    private var resolvedCommerceStateSource: CommerceStateSource?
    private var didResolveCommerceStateSource = false
    private var cancellables: Set<AnyCancellable> = []

    var hasLoadedCommerceStateSource: Bool {
        didResolveCommerceStateSource
    }

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
            && (resolvedCommerceStateSource?.isFirstLaunch ?? false)
    }

    init(
        distributionChannel: DistributionChannel = .current,
        commerceStateSource: CommerceStateSource? = nil,
        commerceStateSourceFactory: (() -> CommerceStateSource?)? = nil
    ) {
        self.distributionChannel = distributionChannel
        self.commerceStateSourceFactory = commerceStateSourceFactory ?? { commerceStateSource }
        self.resolvedCommerceStateSource = commerceStateSource
        self.didResolveCommerceStateSource = commerceStateSource != nil || commerceStateSourceFactory == nil
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
        resolvedCommerceStateSource?.entitlementStatePublisher
            .sink { [weak self] state in
                self?.entitlementState = state
            }
            .store(in: &cancellables)

        resolvedCommerceStateSource?.proSettingsPromptPublisher
            .sink { [weak self] shouldOpen in
                self?.shouldOpenProSettings = shouldOpen
            }
            .store(in: &cancellables)
    }

    private func syncFromSource() {
        entitlementState = resolvedCommerceStateSource?.entitlementState ?? .unrestricted
        shouldOpenProSettings = resolvedCommerceStateSource?.shouldOpenProSettings ?? false
    }

    private var commerceStateSource: CommerceStateSource? {
        if !didResolveCommerceStateSource {
            resolvedCommerceStateSource = commerceStateSourceFactory?()
            didResolveCommerceStateSource = true
            bindIfNeeded()
            syncFromSource()
        }

        return resolvedCommerceStateSource
    }

    private static func makeShared() -> AppAccessController {
        switch DistributionChannel.current {
        case .direct:
            AppAccessController(distributionChannel: .direct)
        case .appStore:
#if APPSTORE
            AppAccessController(distributionChannel: .appStore) {
                ProCommerceStateSource.shared
            }
#else
            AppAccessController(distributionChannel: .appStore)
#endif
        }
    }
}
