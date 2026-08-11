//
//  DirectSupportCard.swift
//  CmdReopen
//

#if !APPSTORE
import AppKit
import SwiftUI

/// The support actions the free build makes available in About.
///
/// The primary action is the App Store copy because that is the only money
/// path this app keeps — no tip jar beside it, so a supporter's money lands
/// where it also buys a review and a ranking. Starring costs nothing and is
/// the next best thing someone can give, so it rides alongside as a quiet
/// secondary action rather than a second button competing for the click.
struct DirectSupportCardRow: View {
    @ObservedObject private var appLanguage = AppLanguage.shared

    var body: some View {
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

                // Brand tint rather than link blue: the pane already spends
                // its accent on this card, and a second accent colour beside
                // the purple button reads as two unrelated systems.
                Button {
                    open(ExternalLinks.githubURL)
                } label: {
                    Label(appLanguage.string(localized: "Star on GitHub",
                        comment: "Secondary support action in the free build's support card."), systemImage: "star")
                        .foregroundStyle(DS.Colors.brandPrimary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .font(.caption)
            }
        }
        .padding(.vertical, DS.Spacing.sm)
    }

    private func open(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }
}
#endif
