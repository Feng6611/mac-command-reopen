//
//  TrialExitOfferView.swift
//  CmdReopen
//

import KikiCommerceCore
import KikiPaywall
import SwiftUI

/// The win-back card shown when someone closes the paywall after their trial
/// ended without buying, and re-opened from the banners while the discount
/// window holds.
///
/// Composed from `KikiPaywall` atoms rather than the paywall sheet: it makes
/// one offer, not a catalog. The stats card carries the argument (what the app
/// already did for this user), the single plan card carries the deal, and the
/// only other way out is the free GitHub build in the footer — deliberately a
/// text link, because it must be available without competing with the offer.
struct TrialExitOfferView: View {
    @ObservedObject var accessModel: CommandAccessModel
    @ObservedObject private var appLanguage = AppLanguage.shared
    @Environment(\.dismiss) private var dismiss

    let offer: TrialExitOffer
    /// Debug previews render the production card without starting the real
    /// user's discount clock.
    var marksOfferShown = true
    var urlOpener: any URLOpening = WorkspaceURLOpener()

    @State private var isPurchasing = false
    @State private var purchaseFailed = false

    var body: some View {
        KikiPaywallShell(
            width: KikiPaywallDefaults.sheetWidth,
            minimumHeight: KikiPaywallDefaults.minimumSheetHeight,
            idealHeight: 460,
            maximumHeight: KikiPaywallDefaults.maximumSheetHeight,
            tint: DS.Colors.brandPrimary,
            showsCloseButton: true,
            onClose: { dismiss() }
        ) {
            VStack(spacing: DS.Spacing.md) {
                Text(appLanguage.string(localized: "20% off, before you go",
                    comment: "Title of the win-back card shown when the paywall is closed after the trial ended."))
                    .font(.title.bold())
                    .multilineTextAlignment(.center)

                Text(subtitle)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
        } content: {
            VStack(spacing: 14) {
                KikiPaywallStatsCard(stats: stats)

                KikiPaywallPlanCard(
                    plan: winbackPlanCard,
                    isSelected: true,
                    tint: DS.Colors.brandPrimary,
                    onSelect: {}
                )
            }
        } actions: {
            VStack(spacing: DS.Spacing.sm) {
                if purchaseFailed {
                    KikiPaywallMessage(
                        appLanguage.string(localized: "The purchase couldn't be completed."),
                        tone: .danger
                    )
                }

                Button(action: purchase) {
                    KikiPaywallActionLabel(
                        title: appLanguage.string(localized: "Get lifetime at 20% off",
                            comment: "Purchase button on the win-back card; buys the discounted lifetime unlock immediately."),
                        isLoading: isPurchasing,
                        tint: DS.Colors.brandPrimary
                    )
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(DS.Colors.brandPrimary)
                .disabled(isPurchasing || !winbackProduct.isAvailable)
                .keyboardShortcut(.defaultAction)
            }
        } footer: {
            Button(appLanguage.string(localized: "No thanks — use the free GitHub build",
                comment: "Footer link on the win-back card to the free build on GitHub.")) {
                openFreeBuild()
            }
            .buttonStyle(.link)
            .font(.caption)
            .frame(maxWidth: .infinity)
        }
        .onAppear {
            if marksOfferShown {
                accessModel.markWinbackOfferShown()
            }
        }
        .task {
            await accessModel.loadOfferings()
        }
    }

    /// Days-granularity urgency, never a ticking clock: the point is that the
    /// price is temporary, not that the user should panic.
    private var subtitle: String {
        if offer.daysRemaining() > 1 {
            return appLanguage.string(localized: "If the price was the sticking point, here’s a smaller one. It holds for 2 days, then it’s gone.",
                comment: "Subtitle of the win-back card while more than a day of the discount window remains.")
        }
        return appLanguage.string(localized: "If the price was the sticking point, here’s a smaller one. It ends today.",
            comment: "Subtitle of the win-back card during the discount window's final day.")
    }

    /// The user's own figures — the argument that the app earned a second
    /// look before the user pays less for it.
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

    private var winbackProduct: KikiAccessPlanProduct {
        accessModel.planProduct(for: .winbackLifetime)
    }

    /// The deal, as one pre-selected card: the discounted price beside the
    /// struck-through full price. Both prices come from the store when the
    /// offering has loaded, so currencies always match.
    private var winbackPlanCard: KikiPaywallPlan {
        let fullPrice = accessModel.planProduct(for: .lifetime).displayPrice

        return KikiPaywallPlan(
            id: winbackProduct.id,
            title: appLanguage.string("Lifetime"),
            displayPrice: winbackProduct.displayPrice,
            originalPrice: fullPrice,
            billingDetail: appLanguage.string("once"),
            badge: appLanguage.string(localized: "20% off",
                comment: "Badge on the win-back plan card naming the discount."),
            isAvailable: winbackProduct.isAvailable
        )
    }

    private func purchase() {
        guard !isPurchasing else { return }
        isPurchasing = true
        purchaseFailed = false

        Task {
            defer { isPurchasing = false }
            do {
                try await accessModel.purchase(.winbackLifetime)
                _ = ReopenStatsStore.shared.requestReviewIfEligible(for: .purchaseCompleted)
                dismiss()
            } catch CommercePurchaseError.purchaseCancelled {
                // The user changed their mind; the card stays as it was.
            } catch {
                purchaseFailed = true
            }
        }
    }

    private func openFreeBuild() {
        dismiss()
        guard let url = URL(string: ExternalLinks.freeBuildURL) else { return }
        urlOpener.open(url)
    }
}

/// The way back to the win-back card while its window holds.
///
/// Appears in Settings › General and in About, and only between the card's
/// first presentation and the window's end — someone who closed the card
/// deserves a route back while the price still stands, but the offer must
/// never advertise itself before the paywall has been declined. Deliberately
/// not in the menu bar: that surface is looked at dozens of times a day, and
/// a promotion there would outlast its welcome by the second glance.
struct WinbackOfferRow: View {
    @ObservedObject var accessModel: CommandAccessModel
    @ObservedObject private var appLanguage = AppLanguage.shared
    let onOpen: () -> Void

    var body: some View {
        if let offer = activeOffer {
            Button(action: onOpen) {
                HStack(spacing: DS.Spacing.sm) {
                    Image(systemName: "tag.fill")
                        .foregroundStyle(DS.Colors.brandPrimary)

                    Text(appLanguage.string(localized: "20% off lifetime",
                        comment: "Title of the banner row that reopens the win-back offer."))
                        .font(.callout.weight(.medium))

                    Spacer(minLength: 0)

                    Text(countdown(for: offer))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    /// The row exists only inside a window that has already been opened by
    /// the card itself. Resolving fresh would show a countdown for a clock
    /// that has not started.
    private var activeOffer: TrialExitOffer? {
        guard accessModel.winbackOfferFirstShownAt != nil else { return nil }
        return TrialExitOffer.resolve(accessModel: accessModel)
    }

    private func countdown(for offer: TrialExitOffer) -> String {
        let days = offer.daysRemaining()
        if days > 1 {
            return appLanguage.string(localized: "\(days) days left",
                comment: "Trial time remaining in the About pane; plural-aware in the catalog.")
        }
        return appLanguage.string(localized: "Ends today",
            comment: "Countdown on the win-back banner during the discount's final day.")
    }
}
