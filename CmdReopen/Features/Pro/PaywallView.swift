#if APPSTORE
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

    var body: some View {
        KikiAccessPaywallSheet(
            manager: accessModel.accessManager,
            context: context.kikiContext,
            copy: KikiAccessPaywallCopy(
                title: "Command Reopen Pro",
                proSubtitle: "Your Pro access is active.",
                trialSubtitle: "Keep minimized windows easy to recover.",
                expiredSubtitle: "Upgrade to continue automatic window reopening.",
                notStartedSubtitle: "Try every Pro feature free for 2 days.",
                features: [
                    "Never lose a minimized window again",
                    "Keep Command-Tab focused and predictable",
                    "Exclude apps that should stay quiet"
                ]
            ),
            footerLinks: footerLinks,
            tint: DS.Colors.brandPrimary,
            onFinish: onFinish
        )
    }

    private var footerLinks: [KikiAccessPaywallLink] {
        [
            makeLink(id: "terms", title: "Terms", value: ExternalLinks.termsURL),
            makeLink(id: "privacy", title: "Privacy", value: ExternalLinks.privacyURL),
            makeLink(id: "support", title: "Support", value: ExternalLinks.contactEmail)
        ].compactMap { $0 }
    }

    private func makeLink(id: String, title: String, value: String) -> KikiAccessPaywallLink? {
        guard let url = URL(string: value) else { return nil }
        return KikiAccessPaywallLink(id: id, title: title, url: url)
    }
}
#endif
