//
//  FeedbackOfferCard.swift
//  CmdReopen
//

#if APPSTORE
import KikiCommerceCore
import KikiSettings
import SwiftUI

/// The one ask the paid build makes in About: tell us what's wrong, and a
/// report we can act on earns a discount code.
///
/// Deliberately shaped like the free build's support card — same slot under
/// the status row, same icon-plus-headline, same left-aligned action — so the
/// two editions read as one app asking for different things rather than two
/// different panes. The body is a single line: the offer is the argument, and
/// a paragraph explaining it would out-weigh the rows it sits above.
struct FeedbackOfferCardRow: View {
    @ObservedObject private var appLanguage = AppLanguage.shared
    @ObservedObject private var accessModel = CommandAccessModel.shared

    var body: some View {
        // Nothing to offer someone who already owns Pro, and an offer they
        // cannot take reads as a pane that has not noticed they paid. Their
        // feedback is still welcome through the Email row above.
        if !accessModel.status.isPro {
            card
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack(spacing: DS.Spacing.sm) {
                Image(systemName: "text.bubble.fill")
                    .font(.title3)
                    .foregroundStyle(DS.Colors.brandPrimary)
                    .frame(width: 36, height: 36)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(DS.Colors.accentTint)
                    )

                Text(appLanguage.string(localized: "Share how you use Command Reopen, get Pro",
                    comment: "Title of the App Store feedback offer card in About."))
                    .font(.headline)

                Spacer(minLength: 0)
            }

            Text(appLanguage.string(localized: "Tell us how it fits your day. An account we can act on earns the lifetime unlock.",
                comment: "Body of the App Store feedback offer card in About."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            // Trailing arrow, matching the link rows below: the same glyph
            // marks the same thing — this opens something outside the app.
            Button {
                KikiSettingsActions.openURL(ExternalLinks.feedbackURL)
            } label: {
                HStack(spacing: DS.Spacing.xs) {
                    Text(appLanguage.string(localized: "Open the form",
                        comment: "Button on the feedback offer card; opens the feedback form in a browser."))
                    Image(systemName: "arrow.up.right")
                        .font(.caption)
                }
                .foregroundStyle(DS.Colors.brandPrimary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .font(.caption)
        }
        .padding(.vertical, DS.Spacing.sm)
    }
}
#endif
