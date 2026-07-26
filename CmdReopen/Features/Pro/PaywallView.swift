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
        // The user's own trial numbers, when there are enough of them to lead
        // with. Resolved once per render and reused for subtitle and stats.
        // Only while a trial is running or has just ended: the copy says "in
        // your trial", which would contradict a sheet offering to start one.
        let receipt = accessModel.status.hasTrialHistory
            ? TrialReceipt.make(trialStartedAt: accessModel.trialStartedAt)
            : nil

        return KikiAccessPaywallSheet(
            manager: accessModel.accessManager,
            context: context.kikiContext,
            copy: KikiAccessPaywallCopy(
                title: String(localized: "Command Reopen Pro", comment: "Product tier name — do not translate."),
                proSubtitle: proSubtitle,
                trialSubtitle: String(localized: "Your free trial is active."),
                // With a receipt the figures above already make the case, so
                // this line only has to name what stops.
                expiredSubtitle: receipt == nil
                    ? String(localized: "Upgrade to continue automatic window reopening.")
                    : String(
                        localized: "Without Pro, Cmd+Tab leaves them minimized again.",
                        comment: "Expired-trial paywall subtitle, naming what stopped working."
                    ),
                notStartedSubtitle: String(localized: "Try every Pro feature free for 2 days. No payment now — nothing auto-renews."),
                features: [
                    String(localized: "Restores minimized and closed windows on Cmd+Tab"),
                    String(localized: "Zero permissions — sandboxed, nothing to grant"),
                    String(localized: "Exclude apps you don’t want restored")
                ],
                purchaseActionTitle: purchaseActionTitle,
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
            stats: ownedAccessStats ?? trialStats(for: receipt),
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
            return String(
                localized: "Turn it back on",
                comment: "Purchase button after the trial ended, when the feature has already stopped."
            )
        }
        return String(
            localized: "Keep it working",
            comment: "Purchase button while the feature is still running on a trial."
        )
    }

    /// What someone who already paid opened this sheet to check: whether the
    /// access is really theirs, and until when. Kept to the facts — they are
    /// past being sold to.
    private var proSubtitle: String {
        switch accessModel.status.renewalState {
        case .renews(let date, _, _):
            return String(
                localized: "Your Pro access renews on \(Self.format(date)).",
                comment: "Paywall subtitle for a subscriber whose plan auto-renews."
            )
        case .ends(let date, _, _):
            return String(
                localized: "Your Pro access ends on \(Self.format(date)). Everything keeps working until then.",
                comment: "Paywall subtitle for a subscriber who turned off auto-renew."
            )
        case nil:
            // Lifetime, and anything else with no expiry to report.
            return String(
                localized: "Your Pro access never expires. Thank you for buying it.",
                comment: "Paywall subtitle for a one-time purchase, which has no renewal date."
            )
        }
    }

    /// Fills the space the plan cards leave behind for an owner, with their own
    /// figures rather than another pitch. `nil` when the user has not paid, so
    /// the trial figures take the slot instead.
    private var ownedAccessStats: [KikiAccessPaywallStat]? {
        guard case .pro(let plan, _) = accessModel.status else {
            return nil
        }

        var stats: [KikiAccessPaywallStat] = []
        let restored = ReopenStatsStore.shared.totalSuccessfulReopens
        if restored > 0 {
            stats.append(
                KikiAccessPaywallStat(
                    id: "restored",
                    value: restored.formatted(),
                    label: String(localized: "Windows restored")
                )
            )
        }
        stats.append(
            KikiAccessPaywallStat(id: "plan", value: plan.title, label: String(localized: "Your plan"))
        )
        return stats
    }

    /// The trial evidence, sized to outweigh the prices it argues against.
    ///
    /// The total leads because it is the argument; the app beside it is what
    /// makes the total legible as the user's own rather than a statistic.
    private func trialStats(for receipt: TrialReceipt?) -> [KikiAccessPaywallStat] {
        guard let receipt else {
            return []
        }

        var stats = [
            KikiAccessPaywallStat(
                id: "trialRestored",
                value: receipt.formattedCount,
                label: String(
                    localized: "Restored in your trial",
                    comment: "Caption under the trial reopen count on the paywall; one line only."
                )
            )
        ]
        if let leadApp = receipt.leadApp {
            // The count is the value and the app name the caption, so a long
            // name is clipped in the smaller type instead of shrinking the
            // figure it belongs to.
            stats.append(
                KikiAccessPaywallStat(
                    id: "trialLeadApp",
                    value: leadApp.count.formatted(),
                    label: leadApp.displayName
                )
            )
        }
        return stats
    }

    private static func format(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .omitted)
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
