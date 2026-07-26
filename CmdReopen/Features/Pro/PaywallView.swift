#if APPSTORE
import KikiCommerceCore
import KikiCommercePresentation
import SwiftUI

enum PaywallPresentationContext {
    case settings
    case onboarding

    var kikiContext: KikiAccessPaywallContext {
        switch self {
        case .settings: .settings
        case .onboarding: .onboarding
        }
    }
}

enum PaywallSource: String {
    case settings
    case statusBar = "status_bar"
    case onboarding
    case trialExpiredLaunch = "trial_expired_launch"
    case expiredReopenNudge = "expired_reopen_nudge"
}

struct PaywallSheetView: View {
    @ObservedObject var accessModel: CommandAccessModel
    let context: PaywallPresentationContext
    let source: PaywallSource
    var onFinish: () -> Void = {}
    var onPurchaseCompleted: () -> Void = {}

    @State private var paywallSessionID = UUID().uuidString.lowercased()
    @State private var didCaptureView = false
    @State private var purchaseAttempt: PurchaseAttempt?

    var body: some View {
        KikiAccessPaywallSheet(
            manager: accessModel.accessManager,
            context: context.kikiContext,
            copy: KikiAccessPaywallCopy(
                title: String(localized: "Command Reopen Pro", comment: "Product tier name — do not translate."),
                proSubtitle: String(localized: "Your Pro access is active."),
                trialSubtitle: String(localized: "Your free trial is active."),
                expiredSubtitle: String(localized: "Upgrade to continue automatic window reopening."),
                notStartedSubtitle: String(localized: "Try every Pro feature free for 2 days. No payment now — nothing auto-renews."),
                features: [
                    String(localized: "Restores minimized and closed windows on Cmd+Tab"),
                    String(localized: "Zero permissions — sandboxed, nothing to grant"),
                    String(localized: "Exclude apps you don’t want restored")
                ],
                purchaseActionTitle: String(localized: "Unlock forever"),
                trialActionTitle: String(localized: "Start free trial"),
                restoreActionTitle: String(localized: "Restore Purchase"),
                doneActionTitle: String(localized: "Done"),
                loadingOptionsMessage: String(localized: "Loading purchase options…"),
                unavailableOptionsMessage: String(localized: "Purchase options are unavailable right now. Try again later or restore an existing purchase."),
                purchaseSuccessMessage: String(localized: "Purchase successful. Pro unlocked."),
                restoreSuccessMessage: String(localized: "Purchase restored."),
                noActivePurchaseMessage: String(localized: "No active purchase found on this account."),
                purchaseErrorMessage: String(localized: "The purchase couldn't be completed.")
            ),
            footerLinks: footerLinks,
            tint: DS.Colors.brandPrimary,
            onFinish: {
                CommandReopenAnalytics.shared.capturePaywallAction(
                    sessionID: paywallSessionID,
                    action: "close",
                    source: source.rawValue,
                    totalSuccessfulReopens: ReopenStatsStore.shared.totalSuccessfulReopens,
                    entitlementState: accessModel.accessEntitlementState.analyticsValue
                )
                let didCompletePurchase = accessModel.accessManager.commerceFeedback == .purchaseSucceeded
                onFinish()

                guard context == .settings, didCompletePurchase else { return }
                DispatchQueue.main.async(execute: onPurchaseCompleted)
            }
        )
        .onAppear(perform: capturePaywallViewIfNeeded)
        .onChange(of: accessModel.accessManager.purchaseInProgressPlanID) { planID in
            handlePurchaseProgress(planID: planID)
        }
        .onChange(of: accessModel.accessManager.isRestoringPurchases) { isRestoring in
            guard isRestoring else { return }
            CommandReopenAnalytics.shared.capturePaywallAction(
                sessionID: paywallSessionID,
                action: "restore",
                source: source.rawValue,
                totalSuccessfulReopens: ReopenStatsStore.shared.totalSuccessfulReopens,
                entitlementState: accessModel.accessEntitlementState.analyticsValue
            )
        }
    }

    private func capturePaywallViewIfNeeded() {
        guard !didCaptureView else { return }
        didCaptureView = true
        let plans = accessModel.availablePlans
        CommandReopenAnalytics.shared.capturePaywallViewed(
            sessionID: paywallSessionID,
            source: source.rawValue,
            defaultPlan: plans.first?.plan.commercePlan.rawValue ?? "unavailable",
            availablePlans: plans.filter(\.isAvailable).map(\.id),
            totalSuccessfulReopens: ReopenStatsStore.shared.totalSuccessfulReopens,
            entitlementState: accessModel.accessEntitlementState.analyticsValue
        )
    }

    private func handlePurchaseProgress(planID: String?) {
        if let planID {
            guard purchaseAttempt == nil else { return }
            let plan = accessModel.availablePlans.first(where: { $0.id == planID })?.plan.commercePlan.rawValue ?? planID
            let attempt = PurchaseAttempt(id: UUID().uuidString.lowercased(), plan: plan, startedAt: Date())
            purchaseAttempt = attempt
            CommandReopenAnalytics.shared.capturePaywallAction(
                sessionID: paywallSessionID,
                action: "purchase",
                plan: plan,
                source: source.rawValue,
                totalSuccessfulReopens: ReopenStatsStore.shared.totalSuccessfulReopens,
                entitlementState: accessModel.accessEntitlementState.analyticsValue
            )
            return
        }

        guard let attempt = purchaseAttempt else { return }
        purchaseAttempt = nil
        let feedback = accessModel.accessManager.commerceFeedback
        let result: String
        let errorCode: String?
        switch feedback {
        case .purchaseSucceeded:
            result = "client_success"
            errorCode = nil
        case .error(let error):
            result = "failed"
            errorCode = Self.analyticsErrorCode(for: error)
        default:
            result = "cancelled"
            errorCode = nil
        }
        CommandReopenAnalytics.shared.capturePurchaseResult(
            attemptID: attempt.id,
            paywallSessionID: paywallSessionID,
            result: result,
            plan: attempt.plan,
            source: source.rawValue,
            durationMilliseconds: max(0, Int(Date().timeIntervalSince(attempt.startedAt) * 1_000)),
            errorCode: errorCode,
            entitlementState: accessModel.accessEntitlementState.analyticsValue
        )
    }

    private static func analyticsErrorCode(for error: CommercePurchaseError) -> String {
        switch error {
        case .network: "network"
        case .purchaseNotAllowed: "purchase_not_allowed"
        case .productUnavailable, .offeringUnavailable, .packageNotFound, .productIdentifierMissing:
            "product_unavailable"
        case .activationPending, .invalidReceipt: "activation_pending"
        case .invalidCredentials, .notConfigured, .invalidConfiguration: "configuration"
        case .purchaseCancelled: "cancelled"
        case .unknown: "unknown"
        }
    }

    private struct PurchaseAttempt {
        let id: String
        let plan: String
        let startedAt: Date
    }

    private var footerLinks: [KikiAccessPaywallLink] {
        [
            makeLink(id: "terms", title: String(localized: "Terms"), value: ExternalLinks.termsURL),
            makeLink(id: "privacy", title: String(localized: "Privacy"), value: ExternalLinks.privacyURL),
            makeLink(id: "support", title: String(localized: "Support"), value: ExternalLinks.contactEmail)
        ].compactMap { $0 }
    }

    private func makeLink(id: String, title: String, value: String) -> KikiAccessPaywallLink? {
        guard let url = URL(string: value) else { return nil }
        return KikiAccessPaywallLink(id: id, title: title, url: url)
    }
}
#endif
