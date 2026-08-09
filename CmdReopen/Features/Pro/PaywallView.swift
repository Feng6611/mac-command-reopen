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
    @ObservedObject private var appLanguage = AppLanguage.shared
    let context: PaywallPresentationContext
    let source: PaywallSource
    var onFinish: () -> Void = {}
    var onPurchaseCompleted: () -> Void = {}

    @State private var paywallSessionID = UUID().uuidString.lowercased()
    @State private var didCaptureView = false
    @State private var purchaseAttempt: PurchaseAttempt?

    var body: some View {
        // The user's trial history changes the expired-state explanation.
        // Only while a trial is running or has just ended: the copy says "in
        // your trial", which would contradict a sheet offering to start one.
        let receipt = accessModel.status.hasTrialHistory
            ? TrialReceipt.make(trialStartedAt: accessModel.trialStartedAt)
            : nil

        return KikiAccessPaywallSheet(
            manager: accessModel.accessManager,
            context: context.kikiContext,
            copy: KikiAccessPaywallCopy(
                title: appLanguage.string(localized: "Command Reopen Pro", comment: "Product tier name — do not translate."),
                proSubtitle: proSubtitle,
                trialSubtitle: appLanguage.string(localized: "Your free trial is active."),
                // With a receipt the figures above already make the case, so
                // this line only has to name what stops.
                expiredSubtitle: receipt == nil
                    ? appLanguage.string(localized: "Upgrade to continue automatic window reopening.")
                    : appLanguage.string(localized: "Without Pro, Cmd+Tab leaves them minimized again.", comment: "Expired-trial paywall subtitle, naming what stopped working."),
                notStartedSubtitle: appLanguage.string(localized: "Try every Pro feature free for 14 days. No payment now — nothing auto-renews."),
                features: [
                    appLanguage.string(localized: "Restores minimized and closed windows on Cmd+Tab"),
                    appLanguage.string(localized: "Zero permissions — sandboxed, nothing to grant"),
                    appLanguage.string(localized: "Exclude apps you don’t want restored")
                ],
                purchaseActionTitle: purchaseActionTitle,
                trialActionTitle: appLanguage.string(localized: "Start free trial"),
                restoreActionTitle: appLanguage.string(localized: "Restore Purchase"),
                doneActionTitle: appLanguage.string(localized: "Done"),
                loadingOptionsMessage: appLanguage.string(localized: "Loading purchase options…"),
                unavailableOptionsMessage: appLanguage.string(localized: "Purchase options are unavailable right now. Try again later or restore an existing purchase."),
                purchaseSuccessMessage: appLanguage.string(localized: "Purchase successful. Pro unlocked."),
                restoreSuccessMessage: appLanguage.string(localized: "Purchase restored."),
                noActivePurchaseMessage: appLanguage.string(localized: "No active purchase found on this account."),
                purchaseErrorMessage: appLanguage.string(localized: "The purchase couldn't be completed.")
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

    /// The purchase button names the outcome, not the transaction.
    ///
    /// It deliberately says nothing about how long access lasts: this one label
    /// is shown for whichever plan happens to be selected, so any promise of
    /// "forever" is false the moment the user picks the yearly card. Duration
    /// belongs on the plan cards, which state it per plan.
    private var purchaseActionTitle: String {
        if case .expired = accessModel.status {
            return appLanguage.string(localized: "Turn it back on", comment: "Purchase button after the trial ended, when the feature has already stopped.")
        }
        return appLanguage.string(localized: "Keep it working", comment: "Purchase button while the feature is still running on a trial.")
    }

    /// What someone who already paid opened this sheet to check: whether the
    /// access is really theirs, and until when. Kept to the facts — they are
    /// past being sold to.
    private var proSubtitle: String {
        switch accessModel.status.renewalState {
        case .renews(let date, _, _):
            return appLanguage.string(localized: "Your Pro access renews on \(format(date)).",
                comment: "Paywall subtitle for a subscriber whose plan auto-renews."
            )
        case .ends(let date, _, _):
            return appLanguage.string(localized: "Your Pro access ends on \(format(date)). Everything keeps working until then.",
                comment: "Paywall subtitle for a subscriber who turned off auto-renew."
            )
        case nil:
            // Lifetime, and anything else with no expiry to report.
            return appLanguage.string(localized: "Your Pro access never expires. Thank you for buying it.",
                comment: "Paywall subtitle for a one-time purchase, which has no renewal date."
            )
        }
    }

    private func format(_ date: Date) -> String {
        date.formatted(.dateTime.year().month(.abbreviated).day().locale(appLanguage.locale))
    }

    private var footerLinks: [KikiAccessPaywallLink] {
        [
            makeLink(id: "terms", title: appLanguage.string(localized: "Terms"), value: ExternalLinks.termsURL),
            makeLink(id: "privacy", title: appLanguage.string(localized: "Privacy"), value: ExternalLinks.privacyURL),
            makeLink(id: "support", title: appLanguage.string(localized: "Support"), value: ExternalLinks.contactEmail)
        ].compactMap { $0 }
    }

    private func makeLink(id: String, title: String, value: String) -> KikiAccessPaywallLink? {
        guard let url = URL(string: value) else { return nil }
        return KikiAccessPaywallLink(id: id, title: title, url: url)
    }
}
#endif
