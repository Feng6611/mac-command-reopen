//
//  DirectSupportCard.swift
//  CmdReopen
//

#if !APPSTORE
import AppKit
import Combine
import SwiftUI

/// Whether the free-build user has told us they already supported the app.
///
/// Payment happens on the App Store and stars happen on GitHub, so this is
/// the user's own word — the same contract as Cat Lock's card. Taking their
/// word costs nothing; not taking it means nagging someone who already paid.
@MainActor
final class DirectSupportState: ObservableObject {
    @Published private(set) var didSupport: Bool

    private let defaults: UserDefaults
    private static let key = "cmdreopenDirectDidSupport"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.didSupport = defaults.bool(forKey: Self.key)
    }

    func markSupported() {
        guard !didSupport else { return }
        didSupport = true
        defaults.set(true, forKey: Self.key)
    }
}

/// The one ask the free build makes, once, in About.
///
/// The primary action is the App Store copy because that is the only money
/// path this app keeps — no tip jar beside it, so a supporter's money lands
/// where it also buys a review and a ranking. The quiet row carries the
/// free actions. "I already did" removes the card for good; declining is
/// an answer too, which is why the card never comes back.
struct DirectSupportCardRow: View {
    @StateObject private var supportState = DirectSupportState()
    @ObservedObject private var appLanguage = AppLanguage.shared

    var body: some View {
        if !supportState.didSupport {
            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                HStack(spacing: DS.Spacing.sm) {
                    Image(systemName: "heart.fill")
                        .font(.title3)
                        .foregroundStyle(DS.Colors.brandPrimary)
                        .frame(width: 36, height: 36)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(DS.Colors.accentTint)
                        )

                    Text(appLanguage.string(localized: "Same app, paid the other way",
                        comment: "Title of the support card in the free build's About pane."))
                        .font(.headline)

                    Spacer(minLength: 0)
                }

                Text(appLanguage.string(localized: "This free build has every feature and always will. The App Store version is identical — buying it funds the work, and you get automatic updates.",
                    comment: "Body of the free build's support card, stating that the paid version unlocks nothing extra."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: DS.Spacing.md) {
                    Button(appLanguage.string(localized: "Get it on the App Store",
                        comment: "Primary button of the free build's support card.")) {
                        open(AppStoreLinks.productURL)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(DS.Colors.brandPrimary)

                    Button(appLanguage.string(localized: "Star on GitHub")) {
                        open(ExternalLinks.githubURL)
                    }
                    .buttonStyle(.link)

                    Button(appLanguage.string(localized: "Follow on X")) {
                        open(ExternalLinks.xURL)
                    }
                    .buttonStyle(.link)

                    Spacer(minLength: 0)

                    Button(appLanguage.string(localized: "I already did",
                        comment: "Dismisses the support card permanently; the user says they already supported the app.")) {
                        supportState.markSupported()
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                }
            }
            .padding(.vertical, DS.Spacing.sm)
        }
    }

    private func open(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }
}
#endif
