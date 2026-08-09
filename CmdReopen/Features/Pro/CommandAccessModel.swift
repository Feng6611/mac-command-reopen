import Combine
import Defaults
import Foundation
import KikiCommerceCore
import KikiRevenueCat

/// Product-specific policy around the shared Kiki access engine.
///
/// Trial calculation, offering resolution, purchase, restore, transaction
/// refresh, and readiness all remain owned by `KikiAccessManager`. This model
/// owns only Command Reopen's onboarding completion and expired-access prompt.
@MainActor
final class CommandAccessModel: ObservableObject {
    static let shared = CommandAccessModel()

    let accessManager: KikiAccessManager
    @Published private(set) var shouldOpenProSettings = false

    private let defaults: UserDefaults
    private var cancellables: Set<AnyCancellable> = []
    private var previousStatus: KikiAccessState
    private var hasPromptedForExpiredStateThisSession = false
    private var hasResolvedInitialReadiness = false

    init(
        defaults: UserDefaults = .standard,
        commerceClient: (any CommerceClient)? = nil,
        now: @escaping () -> Date = Date.init
    ) {
        AppDefaults.migrateLegacyKeys(in: defaults)
        self.defaults = defaults

        if let commerceClient {
            self.accessManager = KikiAccessManager(
                configuration: RevenueCatConfiguration.accessConfiguration,
                defaults: defaults,
                commerceClient: commerceClient,
                now: now
            )
        } else {
            self.accessManager = KikiAccessManager(
                configuration: RevenueCatConfiguration.accessConfiguration,
                revenueCatConfiguration: RevenueCatConfiguration.providerConfiguration,
                defaults: defaults,
                now: now
            )
        }
        self.previousStatus = accessManager.status
        bindAccessState()
    }

    var status: KikiAccessState { accessManager.status }
    var readiness: KikiAccessReadiness { accessManager.readiness }
    var availablePlans: [KikiAccessPlanProduct] { accessManager.availablePlans }
    var lastError: CommercePurchaseError? { accessManager.lastError }
    var purchaseInProgressPlan: CommercePlan? {
        guard let planID = accessManager.purchaseInProgressPlanID else { return nil }
        return RevenueCatConfiguration.accessConfiguration.plans
            .first(where: { $0.id == planID })?
            .commercePlan
    }
    var isRestoringPurchases: Bool { accessManager.isRestoringPurchases }
    var currentEntitlementSnapshot: CommerceEntitlement? { accessManager.currentEntitlementSnapshot }
#if DEBUG
    var debugProAccessOverride: KikiAccessDebugMode? { accessManager.debugProAccessOverride }
#endif

    var isFirstLaunch: Bool {
        !defaults[AppDefaults.hasSeenOnboarding]
    }

    /// Start of the automatic trial, written by the access engine on first
    /// launch. Exposed so the paywall can scope its receipt to the user's own
    /// trial window; `nil` only before that first write.
    var trialStartedAt: Date? {
        defaults[AppDefaults.trialStartDate]
    }

    /// Whether this machine already took the one trial extension the app
    /// offers. Read by `TrialExitOffer` to decide whether it may be made again.
    var hasExtendedTrial: Bool { accessManager.hasExtendedTrial }

    /// Whether the trial-exit offer has already been presented here.
    var hasSeenTrialExitOffer: Bool { defaults[AppDefaults.hasSeenTrialExitOffer] }

    var accessEntitlementState: AccessEntitlementState {
        if case .degraded = readiness, !status.isActive {
            return .trial
        }

        switch status {
        case .notStarted, .expired:
            return .expired
        case .trial:
            return .trial
        case .pro:
            return .pro
        }
    }

    func configureIfNeeded() {
        accessManager.configureIfNeeded()
    }

    func refresh() async {
        await accessManager.refresh()
    }

    func finishOnboardingWithoutTrial() {
        defaults[AppDefaults.hasSeenOnboarding] = true
        objectWillChange.send()
    }

    func loadOfferings() async {
        await accessManager.loadOfferings()
    }

    func purchase(_ plan: CommercePlan) async throws {
        try await accessManager.purchase(planID: plan.rawValue)
        if status.isPro {
            defaults[AppDefaults.hasSeenOnboarding] = true
        }
    }

    func restorePurchases() async throws {
        try await accessManager.restorePurchases()
    }

    func planProduct(for plan: CommercePlan) -> KikiAccessPlanProduct {
        accessManager.planProduct(for: plan.rawValue)
    }

    func markExpiredPromptHandled() {
        shouldOpenProSettings = false
    }

    /// Grants the one trial extension offered when the user closes the paywall
    /// after their trial ended. The original trial start date is preserved by
    /// the access engine, so the app can still report what the trial produced.
    func extendTrial(by duration: TimeInterval) {
        accessManager.extendTrial(by: duration)
    }

    /// Records that the trial-exit offer was made, whatever the user chose.
    func markTrialExitOfferShown() {
        defaults[AppDefaults.hasSeenTrialExitOffer] = true
        objectWillChange.send()
    }

#if DEBUG
    func setDebugProAccessOverride(_ mode: KikiAccessDebugMode) {
        accessManager.setDebugProAccessOverride(mode)
    }

    func clearDebugProAccessOverride() {
        accessManager.clearDebugProAccessOverride()
    }
#endif

    private func bindAccessState() {
        accessManager.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)

        Publishers.CombineLatest(accessManager.$status, accessManager.$readiness)
            .sink { [weak self] status, readiness in
                self?.handle(status: status, readiness: readiness)
            }
            .store(in: &cancellables)
    }

    private func handle(status: KikiAccessState, readiness: KikiAccessReadiness) {
        let isFirstAuthoritativeResult = readiness == .ready && !hasResolvedInitialReadiness
        defer {
            previousStatus = status
            if readiness.hasResolvedInitialRefresh {
                hasResolvedInitialReadiness = true
            }
        }
        guard readiness == .ready,
              status == .expired,
              !isFirstLaunch,
              !hasPromptedForExpiredStateThisSession,
              isFirstAuthoritativeResult || previousStatus != .expired else {
            return
        }

        shouldOpenProSettings = true
        hasPromptedForExpiredStateThisSession = true
    }
}

@available(*, deprecated, renamed: "CommandAccessModel")
typealias ProStatusManager = CommandAccessModel
