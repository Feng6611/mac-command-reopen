//
//  DirectSupportCard.swift
//  CmdReopen
//

#if !APPSTORE
import AppKit
import SwiftUI

/// The support actions available in About for the Direct edition:
/// getting the Mac App Store edition or supporting via Buy Me a Coffee.
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

                Text(appLanguage.string("Support Development"))
                    .font(.headline)

                Spacer(minLength: 0)
            }

            Text(appLanguage.string("Direct is free and full-featured, with optional Advanced Window Restore. The Mac App Store edition includes automatic updates."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: DS.Spacing.md) {
                Button(appLanguage.string("Mac App Store")) {
                    open(AppStoreLinks.productURL)
                }
                .buttonStyle(.borderedProminent)
                .tint(DS.Colors.brandPrimary)

                Button(appLanguage.string("Buy Me a Coffee")) {
                    open(ExternalLinks.buyMeACoffeeURL)
                }
                .buttonStyle(.plain)
                .font(.caption.weight(.medium))
                .foregroundStyle(DS.Colors.brandPrimary)
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
