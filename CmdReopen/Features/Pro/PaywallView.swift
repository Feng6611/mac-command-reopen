#if APPSTORE
import KikiAnalytics
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

/// What the paywall's headline says.
///
/// Onboarding is the first look at the price, before the trial has started:
/// it states what the app does. While a trial runs, its days left sit in the
/// subtitle as status, not as a countdown headline. After the trial ends, the
/// headline says so, because that is when the user has a decision to make.
enum PaywallHeadline: Equatable {
    case onboarding
    case trialEnded
    case product

    static func resolve(status: KikiAccessState, context: PaywallPresentationContext) -> PaywallHeadline {
        switch status {
        case .expired:
            return .trialEnded
        case .notStarted where context == .onboarding:
            return .onboarding
        case .notStarted, .free, .trial, .pro:
            return .product
        }
    }
}

struct PaywallSheetView: View {
    @ObservedObject var accessModel: CommandAccessModel
    @ObservedObject private var appLanguage = AppLanguage.shared
    let context: PaywallPresentationContext
    /// Why the sheet opened; `nil` takes the reason the opening route left in
    /// `PaywallSourceRelay`.
    var source: PaywallSource?
    var onFinish: () -> Void = {}
    var onPurchaseCompleted: () -> Void = {}

    /// Set once a purchase or restore starts in this sheet. The purchase flow
    /// finishes inside the paywall — success message, dismissal, the review
    /// request — so a status that turns Pro mid-flow must not swap the sheet
    /// out from under it.
    @State private var hasTransactedInSheet = false
    /// Whether this sheet opened before the trial started. Kiki finishes the
    /// sheet after "Start free trial" through the same callback as close; a
    /// trial running by then means the user started it here.
    @State private var opensBeforeTrial: Bool?
    @State private var analyticsSession = CommandReopenAnalytics.shared.newSession()
    @State private var viewedAt: Date?
    /// One close per sheet: a close that does not dismiss must not count every tap.
    @State private var hasRecordedClose = false

    var body: some View {
        Group {
            if accessModel.status.isPro, !hasTransactedInSheet {
                // Someone who already paid opened this to check what they
                // own. A catalog of prices, with their plan pre-selected,
                // read as "did my purchase go through?".
                ProAccessStatusView(accessModel: accessModel, onDone: onFinish)
            } else {
                paywall.onAppear {
                    if opensBeforeTrial == nil {
                        opensBeforeTrial = accessModel.status.canStartTrial
                    }
                    PurchaseResultReporter.activePaywallSession = analyticsSession
                    // Starting the trial from this sheet is the paywall button;
                    // closing it clears the claim before any fallback start.
                    if accessModel.status.canStartTrial {
                        TrialStartRelay.set(.paywallButton)
                    }
                    guard viewedAt == nil else { return }
                    viewedAt = Date()
                    let opened = source.map { ($0, PaywallTrigger.user) } ?? PaywallSourceRelay.take()
                    // One viewed event per sheet: the session id dedupes re-appearance.
                    track(.paywallViewed(
                        session: analyticsSession,
                        source: Self.resolvedSource(opened.0, status: accessModel.status),
                        trigger: opened.1,
                        pricesAvailable: pricesAvailable
                    ))
                }
            }
        }
        .onChange(of: accessModel.accessManager.purchaseInProgressPlanID) { planID in
            guard let planID else { return }
            hasTransactedInSheet = true
            trackAction(.purchase, plan: PurchaseResultReporter.planKind(planID))
        }
        .onChange(of: accessModel.accessManager.isRestoringPurchases) { isRestoring in
            guard isRestoring else { return }
            hasTransactedInSheet = true
            trackAction(.restore)
        }
        .onDisappear {
            if PurchaseResultReporter.activePaywallSession == analyticsSession {
                PurchaseResultReporter.activePaywallSession = nil
            }
        }
    }

    /// The expired route also runs before a trial has started, when access
    /// reads as expired but nothing has ended.
    static func resolvedSource(_ source: PaywallSource, status: KikiAccessState) -> PaywallSource {
        if source == .trialExpired, status == .notStarted { return .trialNotStarted }
        return source
    }

    private var pricesAvailable: Bool {
        RevenueCatConfiguration.visiblePaywallPlanIDs.contains {
            accessModel.accessManager.planProduct(for: $0).isAvailable
        }
    }

    private func trackAction(_ action: CommandReopenEvent.PaywallActionKind, plan: CommandReopenEvent.PlanKind? = nil) {
        track(.paywallAction(
            session: analyticsSession,
            action: action,
            plan: plan,
            msSinceView: viewedAt.map { Int(max(0, Date().timeIntervalSince($0)) * 1000) },
            pricesAvailable: pricesAvailable
        ))
    }

    private func track(_ event: CommandReopenEvent) {
        CommandReopenAnalytics.track(event)
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
                trialSubtitle: trialSubtitle,
                expiredSubtitle: appLanguage.string(localized: "Cmd+Tab has stopped restoring your windows.",
                    comment: "Paywall subtitle after the trial ended, naming what stopped working."),
                notStartedSubtitle: appLanguage.string(localized: "Every feature, free for 7 days.",
                    comment: "Paywall subtitle before the free trial has started, mainly at the end of onboarding. One short line."),
                // With the user's own figures on the sheet, feature bullets
                // only push the prices further down. Without them, the
                // bullets are the only case being made.
                features: receipt == nil ? features : [],
                purchaseActionTitle: purchaseActionTitle,
                trialActionTitle: appLanguage.string(localized: "Start 7-day free trial",
                    comment: "Starts the free trial; the primary button at the end of onboarding."),
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
            note: trialNote,
            tint: DS.Colors.brandPrimary,
            onFinish: {
                let didCompletePurchase = accessModel.accessManager.commerceFeedback == .purchaseSucceeded
                if !didCompletePurchase {
                    let didStartTrial: Bool
                    if opensBeforeTrial == true, case .trial = accessModel.status {
                        didStartTrial = true
                    } else {
                        didStartTrial = false
                    }
                    if didStartTrial {
                        trackAction(.startTrial)
                    } else if !hasRecordedClose {
                        hasRecordedClose = true
                        trackAction(.close)
                    }
                }
                TrialStartRelay.set(nil)
                onFinish()

                guard context == .settings, didCompletePurchase else { return }
                onPurchaseCompleted()
            }
        )
    }

    private var headline: String {
        switch PaywallHeadline.resolve(status: accessModel.status, context: context) {
        case .onboarding:
            return appLanguage.string(localized: "Keep every window one Cmd+Tab away",
                comment: "Paywall title at the end of onboarding, before the free trial starts.")
        case .trialEnded:
            return appLanguage.string(localized: "Your free trial has ended",
                comment: "Paywall title after the trial ended without a purchase.")
        case .product:
            return appLanguage.string(localized: "Command Reopen Pro", comment: "Product tier name — do not translate.")
        }
    }

    /// Trial status, not a countdown: the days left read as a fact.
    private var trialSubtitle: String {
        guard case .trial(.time(let days, _)) = accessModel.status, days > 1 else {
            return appLanguage.string(localized: "Free trial · ends today",
                comment: "Paywall subtitle on the free trial's last day.")
        }
        return appLanguage.string(localized: "Free trial · \(days) days left",
            comment: "Paywall subtitle while the free trial runs; plural-aware in the catalog.")
    }

    /// Shown only while the trial can still be started, where charge anxiety
    /// would otherwise stop someone from starting it.
    private var trialNote: String? {
        guard accessModel.status.canStartTrial else { return nil }
        return appLanguage.string(localized: "No payment details needed. Nothing renews.",
            comment: "Paywall footnote before the free trial starts.")
    }

    /// Onboarding's paywall is a fixed 520-point card inside the welcome
    /// window, and two full-width buttons sit under the plan. Someone who has
    /// just installed the app was asked for no permission, so that bullet is
    /// left to Settings, where the card can grow.
    private var features: [String] {
        let restores = appLanguage.string(localized: "Restores minimized and closed windows on Cmd+Tab")
        let everyMac = appLanguage.string(localized: "Buy once, use on every Mac with your Apple Account",
            comment: "Paywall feature: a Mac App Store purchase restores on every Mac signed in to the same Apple Account.")
        if context == .onboarding {
            return [restores, everyMac]
        }
        return [restores, appLanguage.string(localized: "Zero permissions — sandboxed, nothing to grant"), everyMac]
    }

    /// After the trial ends the button names the outcome, because the feature
    /// has already stopped. Before that it names the one plan the paywall
    /// lists; the price stays on the card, in the storefront's currency.
    private var purchaseActionTitle: String {
        if case .expired = accessModel.status {
            return appLanguage.string(localized: "Turn it back on", comment: "Purchase button after the trial ended, when the feature has already stopped.")
        }
        return appLanguage.string(localized: "Buy Lifetime", comment: "Purchase button before the trial ends; Lifetime is the plan name.")
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
            // Lifetime is the only plan listed; "Best Value" compared it with nothing.
            badge = nil
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
