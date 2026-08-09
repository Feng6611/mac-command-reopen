//
//  TrialExitOffer.swift
//  CmdReopen
//

import Foundation
import KikiCommerceCore

/// What Command Reopen offers someone who closes the paywall after their trial
/// ended without buying.
///
/// Closing that sheet is the only moment the app knows for certain that the
/// user decided not to pay, and it is the last one before they either forget
/// the app or delete it. Rather than let them leave with nothing, the app makes
/// one offer: more time, a way to say what was wrong, or the free Community
/// edition.
///
/// The offer is deliberately scarce. It is made **once per machine**, and never
/// to someone who already took the extension, because a trial that can always
/// be renewed is not a trial — it is a free app with extra steps.
struct TrialExitOffer: Equatable {
    /// How much more trial time the offer grants.
    ///
    /// The same fourteen days as the original trial. A shorter "last chance"
    /// window would read as a haggle; the point of the offer is that the user
    /// did not get to a decision, and the honest fix is to give them the same
    /// run again.
    static let extraTrialDuration: TimeInterval = 14 * 24 * 60 * 60

    /// The figures the card argues from. Never `nil` in a resolved offer — see
    /// `resolve(...)` for why an offer without them is not made at all.
    let receipt: TrialReceipt

#if DEBUG
    /// Stable content for the Debug Settings preview. It lets development
    /// builds exercise the real retention card without changing trial state
    /// or waiting for an expired trial with enough usage history.
    static let debugPreview = TrialExitOffer(
        receipt: TrialReceipt(
            reopenCount: 37,
            leadApp: ReopenStatsStore.AppStat(
                bundleID: "com.apple.dt.Xcode",
                displayName: "Xcode",
                count: 12
            )
        )!
    )
#endif

    /// Decides whether the offer may be made.
    ///
    /// - Parameters:
    ///   - status: current access state. Only an expired trial qualifies; a
    ///     running trial has not asked the user for a decision yet, and a
    ///     purchase has already got one.
    ///   - hasExtendedTrial: whether an extension was already granted here.
    ///   - hasBeenShown: whether the card was already presented here, whatever
    ///     the user picked. Declining once is an answer.
    ///   - receipt: what the app did during the trial. Required: without it the
    ///     card has no argument, and a second free fortnight spent on someone
    ///     who never adopted the feature buys neither a sale nor a signal.
    static func resolve(
        status: KikiAccessState,
        hasExtendedTrial: Bool,
        hasBeenShown: Bool,
        receipt: TrialReceipt?
    ) -> TrialExitOffer? {
        guard status == .expired,
              !hasExtendedTrial,
              !hasBeenShown,
              let receipt else {
            return nil
        }

        return TrialExitOffer(receipt: receipt)
    }
}

@MainActor
extension TrialExitOffer {
    /// Resolves the offer against live app state.
    static func resolve(accessModel: CommandAccessModel) -> TrialExitOffer? {
        resolve(
            status: accessModel.status,
            hasExtendedTrial: accessModel.hasExtendedTrial,
            hasBeenShown: accessModel.hasSeenTrialExitOffer,
            receipt: TrialReceipt.make(trialStartedAt: accessModel.trialStartedAt)
        )
    }
}
