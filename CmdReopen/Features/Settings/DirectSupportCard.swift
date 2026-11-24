//
//  DirectSupportCard.swift
//  CmdReopen
//

#if !APPSTORE
import AppKit
import SwiftUI

/// The one support ask the free build makes in About (D-005).
///
/// The App Store copy is the only money path this app keeps, so it is the
/// single button — no tip jar beside it, so a supporter's money lands where it
/// also buys a review and a ranking. The body says plainly what buying adds
/// (automatic updates) and what it does not have (Advanced Window Restore).
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
                        RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                            .fill(DS.Colors.accentTint)
                    )

                Text(appLanguage.string(localized: "Support Command Reopen",
                    comment: "Title of the support card in the free GitHub build's About pane, and heading of its note on the final onboarding step."))
                    .font(.headline)

                Spacer(minLength: 0)
            }

            Text(appLanguage.string(localized: "This free build has every feature and always will. Buying the App Store version pays for the work and adds automatic updates. Advanced Window Restore is only in this build.",
                comment: "Body of the free GitHub build's support card and onboarding note. The paid App Store version unlocks nothing extra and lacks the opt-in Advanced Window Restore."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button(appLanguage.string("Get on Mac App Store")) {
                open(AppStoreLinks.productURL)
            }
            .buttonStyle(.borderedProminent)
            .tint(DS.Colors.brandPrimary)
        }
        .padding(.vertical, DS.Spacing.sm)
    }

    private func open(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }
}
#endif
