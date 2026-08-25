//
//  AppAccessController.swift
//  CmdReopen
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

    /// App-facing readiness policy. Keeping these answers here prevents the
    /// lifecycle coordinator from reaching through the access seam to the
    /// App Store-specific model.
    var hasResolvedInitialCommerceRefresh: Bool {
        switch distributionChannel {
        case .appStore:
            return commerceStateSource?.hasResolvedInitialRefresh ?? false
        case .direct:
            return true
        }
    }

    var allowsAutomaticAccessPresentation: Bool {
        switch distributionChannel {
        case .appStore:
            return commerceStateSource?.allowsAutomaticPresentation ?? false
        case .direct:
            return true
        }
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

    /// Whether this launch should present onboarding.
    ///
    /// Both editions show it: the tutorial explains the one interaction the
    /// product is, and the free build needs that explanation more than the
    /// paid one — nothing visibly happens when it is installed. Only the way
    /// "first launch" is known differs. The App Store build asks the commerce
    /// state, which knows whether a trial has ever been opened; the free build
    /// has no commerce state and reads the completion flag onboarding itself
    /// writes.
    var shouldShowOnboarding: Bool {
        switch distributionChannel {
        case .appStore:
            resolvedCommerceStateSource?.isFirstLaunch ?? false
        case .direct:
            !UserDefaults.standard.bool(forKey: AppDefaults.RawKey.hasSeenOnboarding)
        }
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
        self.entitlementState = commerceStateSource?.entitlementState ?? Self.initialEntitlementState(for: distributionChannel)
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
        entitlementState = resolvedCommerceStateSource?.entitlementState ?? Self.initialEntitlementState(for: distributionChannel)
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

    private static func initialEntitlementState(for distributionChannel: DistributionChannel) -> AccessEntitlementState {
        switch distributionChannel {
        case .direct:
            .unrestricted
        case .appStore:
            .trial
        }
    }
}
