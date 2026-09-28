#if APPSTORE
import KikiCommerceCore
import KikiCommercePresentation
import KikiPaywall
import SwiftUI

/// The trial receipt as paywall stats: the total first, as the argument, and
/// the app the user recognises fastest beside it, so the number reads as
/// theirs rather than as a statistic.
///
/// Same labels as the win-back card: one receipt, one way it reads, whichever
/// sheet shows it.
@MainActor
enum TrialReceiptStats {
    static func make(for receipt: TrialReceipt, language: AppLanguage = .shared) -> [KikiAccessPaywallStat] {
        var stats = [
            KikiAccessPaywallStat(
                id: "trialRestored",
                value: receipt.formattedCount,
                label: language.string(localized: "windows restored in trial",
                    comment: "Label under the number of windows the app restored during the trial.")
            )
        ]
        if let leadApp = receipt.leadApp {
            stats.append(
                KikiAccessPaywallStat(
                    id: "trialLeadApp",
                    value: leadApp.displayName,
                    label: language.string(localized: "most restored app",
                        comment: "Label under the name of the app whose windows were restored most during the trial.")
                )
            )
        }
        return stats
    }
}

/// What a paying user sees when they open the access sheet: what they own,
/// until when, and what it has done for them — no prices, no plan picker.
///
/// Composed from `KikiPaywall` atoms rather than `KikiAccessPaywallSheet`,
/// which is a purchase surface: it always lists plans, and with none to list
/// it reports that purchase options are unavailable.
struct ProAccessStatusView: View {
    @ObservedObject var accessModel: CommandAccessModel
    @ObservedObject private var appLanguage = AppLanguage.shared
    @Environment(\.dismiss) private var dismiss
    let onDone: () -> Void

    var body: some View {
        KikiPaywallShell(
            width: KikiPaywallDefaults.sheetWidth,
            // Header, one stat row and one button: the shared paywall minimum
            // would leave a band of empty space above Done.
            minimumHeight: 300,
            idealHeight: 300,
            maximumHeight: KikiPaywallDefaults.maximumSheetHeight,
            tint: DS.Colors.brandPrimary,
            showsCloseButton: true,
            onClose: finish
        ) {
            KikiPaywallHeader(
                title: appLanguage.string(localized: "Command Reopen Pro", comment: "Product tier name — do not translate."),
                subtitle: subtitle
            )
        } content: {
            KikiPaywallStatsCard(stats: stats)
        } actions: {
            Button(action: finish) {
                KikiPaywallActionLabel(
                    title: appLanguage.string(localized: "Done"),
                    isLoading: false,
                    tint: DS.Colors.brandPrimary
                )
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(DS.Colors.brandPrimary)
            .keyboardShortcut(.defaultAction)
        } footer: {
            EmptyView()
        }
    }

    private func finish() {
        dismiss()
        onDone()
    }

    /// Kept to the facts — whether the access is really theirs, and until
    /// when. They are past being sold to.
    private var subtitle: String {
        switch accessModel.status.renewalState {
        case .renews(let date, _, _):
            return appLanguage.string(localized: "Your Pro access renews on \(format(date)).",
                comment: "Paywall subtitle for a subscriber whose plan auto-renews."
            )
        case .ends(let date, _, _):
            return appLanguage.string(localized: "Your Pro access ends on \(format(date)). Everything keeps working until then.",
                comment: "Paywall subtitle for a subscriber who turned off auto-renew."
            )
        case nil:
            // Lifetime, and anything else with no expiry to report.
            return appLanguage.string(localized: "Your Pro access never expires. Thank you for buying it.",
                comment: "Paywall subtitle for a one-time purchase, which has no renewal date."
            )
        }
    }

    private var stats: [KikiPaywallStatConfig] {
        var stats: [KikiPaywallStatConfig] = []
        let restored = ReopenStatsStore.shared.totalSuccessfulReopens
        if restored > 0 {
            stats.append(KikiPaywallStatConfig(
                id: "restored",
                value: restored.formatted(),
                label: appLanguage.string(localized: "Windows restored",
                    comment: "Caption under the lifetime reopen count on the paywall; one line only.")
            ))
        }
        if case .pro(let plan, _) = accessModel.status {
            stats.append(KikiPaywallStatConfig(
                id: "plan",
                value: planTitle(for: plan),
                label: appLanguage.string(localized: "Your plan",
                    comment: "Caption under the purchased plan name on the paywall; one line only.")
            ))
        }
        return stats
    }

    private func planTitle(for plan: KikiAccessPlan) -> String {
        switch plan.commercePlan {
        case .yearly: appLanguage.string("Yearly")
        case .lifetime, .winbackLifetime: appLanguage.string("Lifetime")
        default: plan.title
        }
    }

    private func format(_ date: Date) -> String {
        date.formatted(.dateTime.year().month(.abbreviated).day().locale(appLanguage.locale))
    }
}
#endif
