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

struct PaywallSheetView: View {
    @ObservedObject var accessModel: CommandAccessModel
    let context: PaywallPresentationContext
    var onFinish: () -> Void = {}
    var onPurchaseCompleted: () -> Void = {}

    var body: some View {
        KikiAccessPaywallSheet(
            manager: accessModel.accessManager,
            context: context.kikiContext,
            copy: KikiAccessPaywallCopy(
                title: String(localized: "Command Reopen Pro", comment: "Product tier name — do not translate."),
                proSubtitle: String(localized: "Your Pro access is active."),
                trialSubtitle: String(localized: "Keep minimized windows easy to recover."),
                expiredSubtitle: String(localized: "Upgrade to continue automatic window reopening."),
                notStartedSubtitle: String(localized: "Try every Pro feature free for 2 days."),
                features: [
                    String(localized: "Never lose a minimized window again"),
                    String(localized: "Keep Command-Tab focused and predictable"),
                    String(localized: "Exclude apps that should stay quiet")
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
                let didCompletePurchase = accessModel.accessManager.commerceFeedback == .purchaseSucceeded
                onFinish()

                guard context == .settings, didCompletePurchase else { return }
                DispatchQueue.main.async(execute: onPurchaseCompleted)
            }
        )
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
