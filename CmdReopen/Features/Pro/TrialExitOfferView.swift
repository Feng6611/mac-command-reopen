//
//  TrialExitOfferView.swift
//  CmdReopen
//

import AppKit
import KikiPaywall
import SwiftUI

/// Presents `TrialExitOfferView` and carries out what the user picks.
///
/// Every route marks the offer as made before it acts. Declining is an answer,
/// and a card that reappeared until the user took one of its deals would be the
/// nag this feature exists to avoid.
struct TrialExitOfferSheet: View {
    @ObservedObject var accessModel: CommandAccessModel
    @Environment(\.dismiss) private var dismiss

    let offer: TrialExitOffer
    var urlOpener: any URLOpening = WorkspaceURLOpener()

    var body: some View {
        TrialExitOfferView(
            offer: offer,
            onExtendTrial: {
                complete { accessModel.extendTrial(by: TrialExitOffer.extraTrialDuration) }
            },
            onSendFeedback: {
                complete { open(TrialExitOfferMail.url(language: AppLanguage.shared)) }
            },
            onUseCommunityEdition: {
                complete { open(URL(string: ExternalLinks.communityEditionURL)) }
            },
            onDecline: {
                complete {}
            }
        )
    }

    private func complete(_ action: () -> Void) {
        accessModel.markTrialExitOfferShown()
        action()
        dismiss()
    }

    private func open(_ url: URL?) {
        guard let url else { return }
        urlOpener.open(url)
    }
}

/// The feedback message the offer's second button opens.
///
/// Prefilled with the one question worth asking at this moment, because a blank
/// compose window at the end of a trial is usually closed unanswered.
enum TrialExitOfferMail {
    static func url(language: AppLanguage) -> URL? {
        let subject = language.string(localized: "Command Reopen — what I was missing",
            comment: "Subject line of the prefilled feedback email offered when a trial ends.")
        let body = language.string(localized: "What stopped me from upgrading:\n\n\nWhat I expected it to do:\n\n",
            comment: "Prefilled body of the trial feedback email. Each line is a prompt the user answers.")

        var components = URLComponents(string: ExternalLinks.contactEmail)
        components?.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body)
        ]
        return components?.url
    }
}

/// The card shown once, when someone closes the paywall after their trial
/// ended without buying.
///
/// Composed from `KikiPaywall` atoms rather than the paywall sheet itself: this
/// is not a paywall. It sells nothing, has no plan cards, and every route off
/// it costs the user nothing. Reusing the sheet would have meant a purchase
/// layout with the purchase removed.
///
/// The order of the three routes is deliberate. More time is first because the
/// user is already leaving and it is the only option with no cost to them;
/// keeping them installed is what makes the other two possible later. Feedback
/// is second because it is the app's only signal now that nothing is measured.
/// The Community edition is a footer link — honest to offer, but it must not
/// outrank a route that could still end in a sale.
struct TrialExitOfferView: View {
    @ObservedObject private var appLanguage = AppLanguage.shared

    let offer: TrialExitOffer
    /// Grants the extra fortnight. The view does not touch access state.
    let onExtendTrial: () -> Void
    let onSendFeedback: () -> Void
    let onUseCommunityEdition: () -> Void
    let onDecline: () -> Void

    var body: some View {
        KikiPaywallShell(
            width: KikiPaywallDefaults.sheetWidth,
            height: Self.height,
            tint: DS.Colors.brandPrimary,
            showsCloseButton: true,
            onClose: onDecline
        ) {
            VStack(spacing: DS.Spacing.md) {
                Text(appLanguage.string(localized: "Take another 14 days",
                    comment: "Title of the card offered when the user closes the paywall after their trial ended."))
                    .font(.title.bold())
                    .multilineTextAlignment(.center)

                Text(appLanguage.string(localized: "No card, no payment. If it still isn’t worth it in two weeks, that’s a real answer.",
                    comment: "Subtitle of the trial extension offer, stating that the extension costs nothing."))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
        } content: {
            KikiPaywallStatsCard(stats: stats)
        } actions: {
            VStack(spacing: DS.Spacing.sm) {
                Button(action: onExtendTrial) {
                    KikiPaywallActionLabel(
                        title: appLanguage.string(localized: "Give me 14 more days",
                            comment: "Primary button that extends the expired trial by another fourteen days."),
                        isLoading: false,
                        tint: DS.Colors.brandPrimary
                    )
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(DS.Colors.brandPrimary)
                .keyboardShortcut(.defaultAction)

                Button(action: onSendFeedback) {
                    KikiPaywallActionLabel(
                        title: appLanguage.string(localized: "Tell me what’s missing",
                            comment: "Secondary button that opens an email to the developer about why the user did not upgrade."),
                        isLoading: false,
                        tint: DS.Colors.brandPrimary
                    )
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        } footer: {
            VStack(spacing: DS.Spacing.sm) {
                Text(appLanguage.string(localized: "Write back about what didn’t work and I’ll reply with a discount code.",
                    comment: "Footnote explaining what the user gets for sending feedback."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Button(appLanguage.string(localized: "Use the free Community edition",
                    comment: "Footer link to the free, non-commercial edition on GitHub.")) {
                    onUseCommunityEdition()
                }
                .buttonStyle(.link)
                .font(.caption)
            }
            .frame(maxWidth: .infinity)
        }
    }

    /// Fits the header, one stats card, two buttons and the footer. The card
    /// has one fixed shape — unlike the paywall it has no state-dependent rows
    /// — so it states its height rather than deriving one.
    private static let height: CGFloat = 440

    /// The user's own figures, which are the whole argument for a second run:
    /// the app already did this much for them and then stopped.
    private var stats: [KikiPaywallStatConfig] {
        var stats = [
            KikiPaywallStatConfig(
                value: offer.receipt.formattedCount,
                label: appLanguage.string(localized: "windows restored",
                    comment: "Label under the number of windows the app restored during the trial.")
            )
        ]

        if let leadApp = offer.receipt.leadApp {
            stats.append(
                KikiPaywallStatConfig(
                    value: leadApp.displayName,
                    label: appLanguage.string(localized: "restored most often",
                        comment: "Label under the name of the app whose windows were restored most during the trial.")
                )
            )
        }

        return stats
    }
}
