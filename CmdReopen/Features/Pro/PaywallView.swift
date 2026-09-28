#if APPSTORE
import KikiCommerceCore
import KikiCommercePresentation
import KikiPaywall
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

/// What the paywall's headline says, decided by access state alone.
///
/// The product name told a user whose trial had just ended nothing about why
/// Cmd+Tab stopped working. The headline now states the one fact the user
/// opened the sheet — or had it opened for them — to learn.
enum PaywallHeadline: Equatable {
    case trialEnds(inDays: Int)
    case trialEndsToday
    case trialEnded
    case product

    static func resolve(status: KikiAccessState) -> PaywallHeadline {
        switch status {
        case .trial(.time(let daysRemaining, _)):
            return daysRemaining > 1 ? .trialEnds(inDays: daysRemaining) : .trialEndsToday
        case .expired:
            return .trialEnded
        case .notStarted, .trial, .pro:
            return .product
        }
    }
}

struct PaywallSheetView: View {
    @ObservedObject var accessModel: CommandAccessModel
    @ObservedObject private var appLanguage = AppLanguage.shared
    let context: PaywallPresentationContext
    var onFinish: () -> Void = {}
    var onPurchaseCompleted: () -> Void = {}

    /// Set once a purchase or restore starts in this sheet. The purchase flow
    /// finishes inside the paywall — success message, dismissal, the review
    /// request — so a status that turns Pro mid-flow must not swap the sheet
    /// out from under it.
    @State private var hasTransactedInSheet = false

    var body: some View {
        Group {
            if accessModel.status.isPro, !hasTransactedInSheet {
                // Someone who already paid opened this to check what they
                // own. A catalog of prices, with their plan pre-selected,
                // read as "did my purchase go through?".
                ProAccessStatusView(accessModel: accessModel, onDone: onFinish)
            } else {
                paywall
            }
        }
        .onChange(of: accessModel.accessManager.purchaseInProgressPlanID) { planID in
            if planID != nil { hasTransactedInSheet = true }
        }
        .onChange(of: accessModel.accessManager.isRestoringPurchases) { isRestoring in
            if isRestoring { hasTransactedInSheet = true }
        }
    }

    private var paywall: some View {
        // The user's own trial figures are the argument for paying, so they
        // lead the sheet as its stat card. Only while a trial is running or
        // has just ended: the labels say "in trial", which would contradict a
        // sheet offering to start one.
        let receipt = accessModel.status.hasTrialHistory
            ? TrialReceipt.make(trialStartedAt: accessModel.trialStartedAt)
            : nil

        return KikiAccessPaywallSheet(
            manager: accessModel.accessManager,
            context: context.kikiContext,
            copy: KikiAccessPaywallCopy(
                title: headline,
                proSubtitle: "",
                trialSubtitle: appLanguage.string(localized: "Choose a plan to keep Cmd+Tab bringing your windows back after the trial.",
                    comment: "Paywall subtitle while the free trial is still running."),
                expiredSubtitle: appLanguage.string(localized: "Cmd+Tab has stopped restoring your windows.",
                    comment: "Paywall subtitle after the trial ended, naming what stopped working."),
                notStartedSubtitle: appLanguage.string(localized: "Try every Pro feature free for 14 days. No payment now — nothing auto-renews."),
                // With the user's own figures on the sheet, feature bullets
                // only push the prices further down. Without them, the
                // bullets are the only case being made.
                features: receipt == nil ? features : [],
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
            stats: receipt.map { TrialReceiptStats.make(for: $0) } ?? [],
            footerLinks: footerLinks,
            displayPlanIDs: RevenueCatConfiguration.visiblePaywallPlanIDs,
            planPresentation: localizedPlanPresentation(for:),
            tint: DS.Colors.brandPrimary,
            onFinish: {
                let didCompletePurchase = accessModel.accessManager.commerceFeedback == .purchaseSucceeded
                onFinish()

                guard context == .settings, didCompletePurchase else { return }
                onPurchaseCompleted()
            }
        )
    }

    private var headline: String {
        switch PaywallHeadline.resolve(status: accessModel.status) {
        case .trialEnds(let days):
            return appLanguage.string(localized: "Your free trial ends in \(days) days",
                comment: "Paywall title while the trial runs; plural-aware in the catalog.")
        case .trialEndsToday:
            return appLanguage.string(localized: "Your free trial ends today",
                comment: "Paywall title during the trial's final day.")
        case .trialEnded:
            return appLanguage.string(localized: "Your free trial has ended",
                comment: "Paywall title after the trial ended without a purchase.")
        case .product:
            return appLanguage.string(localized: "Command Reopen Pro", comment: "Product tier name — do not translate.")
        }
    }

    private var features: [String] {
        [
            appLanguage.string(localized: "Restores minimized and closed windows on Cmd+Tab"),
            appLanguage.string(localized: "Zero permissions — sandboxed, nothing to grant"),
            appLanguage.string(localized: "Exclude apps you don’t want restored")
        ]
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

    /// The access manager retains its commerce configuration for the whole
    /// process. Resolve plan-card copy in this observed view so changing the
    /// language in Settings immediately updates an already-open paywall.
    private func localizedPlanPresentation(for product: KikiAccessPlanProduct) -> KikiPaywallPlanPresentation {
        let plan = product.plan.commercePlan
        let title: String
        let billingDetail: String
        let badge: String?

        switch plan {
        case .yearly:
            title = appLanguage.string(localized: "Yearly")
            billingDetail = appLanguage.string(localized: "per year")
            badge = nil
        case .lifetime, .winbackLifetime:
            title = appLanguage.string(localized: "Lifetime")
            billingDetail = appLanguage.string(localized: "once")
            badge = plan == .lifetime ? appLanguage.string(localized: "Best Value") : nil
        default:
            title = product.title
            billingDetail = product.billingDetail
            badge = product.badge
        }

        return KikiPaywallPlanPresentation(
            id: product.id,
            title: title,
            displayPrice: product.displayPrice,
            billingDetail: billingDetail,
            badge: badge,
            isAvailable: product.isAvailable
        )
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
