//
//  TrialExitOffer.swift
//  CmdReopen
//

import Foundation
import KikiCommerceCore

/// The win-back offer Command Reopen makes when someone closes the paywall
/// after their trial ended without buying: the lifetime unlock at 20% off,
/// purchasable on the spot, or the free GitHub build.
///
/// Closing that paywall is the only moment the app knows for certain that the
/// user decided not to pay, and the last one before they either forget the app
/// or delete it. The offer is a separate discounted SKU rather than a code:
/// macOS has no in-app redemption sheet, and a code would send the user
/// hunting for the App Store's redeem screen at the exact moment they are
/// already leaving.
///
/// The discount runs for **two days from its first presentation** and never
/// returns. Inside that window the card can be reopened from the banners in
/// Settings and About — someone who closed it deserves a way back while the
/// price still holds. A discount that quietly came back later would teach
/// users that the full price is never real.
struct TrialExitOffer: Equatable {
    /// How long the discount holds after the user first sees it. Two days is
    /// long enough to sleep on it, short enough that "it ends" is true.
    static let discountWindow: TimeInterval = 2 * 24 * 60 * 60

    /// The figures the card argues from. Never `nil` in a resolved offer —
    /// see `resolve(...)` for why an offer without them is not made at all.
    let receipt: TrialReceipt

    /// When the discount stops. Drives the card's urgency line and the
    /// banners' countdown.
    let windowEndsAt: Date

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
        )!,
        windowEndsAt: Date().addingTimeInterval(discountWindow)
    )
#endif

    /// Decides whether the offer may be made or re-shown.
    ///
    /// - Parameters:
    ///   - status: current access state. Only an expired trial qualifies; a
    ///     running trial has not asked the user for a decision yet, and a
    ///     purchase has already got one.
    ///   - firstShownAt: when the offer was first presented here, `nil` if
    ///     never. Before the first show the offer is fresh; inside the window
    ///     it may be re-presented; after it, it is gone for good.
    ///   - now: the current moment, injectable for tests.
    ///   - receipt: what the app did during the trial. Required: the card
    ///     argues from the user's own figures, and a discount pitched at
    ///     someone the app never helped is spam with a price on it.
    static func resolve(
        status: KikiAccessState,
        firstShownAt: Date?,
        now: Date = Date(),
        receipt: TrialReceipt?
    ) -> TrialExitOffer? {
        guard status == .expired, let receipt else {
            return nil
        }

        let windowEndsAt = (firstShownAt ?? now).addingTimeInterval(discountWindow)
        guard now < windowEndsAt else {
            return nil
        }

        return TrialExitOffer(receipt: receipt, windowEndsAt: windowEndsAt)
    }

    /// Whole days left before the window closes, rounded up: a fresh offer
    /// reports 2, and anything within the final day reports 1. Feeds the
    /// countdown copy, which says "ends today" at 1.
    func daysRemaining(now: Date = Date()) -> Int {
        max(0, Int(ceil(windowEndsAt.timeIntervalSince(now) / 86_400)))
    }
}

@MainActor
extension TrialExitOffer {
    /// How much of the window is left, in the words every surface uses.
    ///
    /// Three surfaces render this countdown and each used to phrase it for
    /// itself, which is how the final day came to read "Ends today" on one
    /// banner and "1 day left" on another for the same offer at the same
    /// moment. Whole days only: the point is that the price is temporary,
    /// not that the user should watch a clock.
    func countdownText(now: Date = Date()) -> String {
        let language = AppLanguage.shared
        let days = daysRemaining(now: now)
        guard days > 1 else {
            return language.string(localized: "Ends today",
                comment: "Countdown on the win-back banner during the discount's final day.")
        }
        return language.string(localized: "\(days) days left",
            comment: "Trial time remaining in the About pane; plural-aware in the catalog.")
    }

    /// Resolves the offer against live app state.
    static func resolve(accessModel: CommandAccessModel, now: Date = Date()) -> TrialExitOffer? {
#if DEBUG
        // Debug Settings can open the window without waiting two days for it.
        //
        // It stands in for the usage history only — a picker cannot fabricate
        // five restores spread across a trial. The access state stays the
        // real one, so the win-back row in Debug Settings does nothing until
        // Pro access is also set to Expired. Substituting the state as well
        // made the banners appear for a Pro user, which is precisely the
        // mismatch between the debug panel and the app it is meant to mirror.
        if accessModel.isWinbackDebugForced, let firstShownAt = accessModel.winbackOfferFirstShownAt {
            return resolve(
                status: accessModel.status,
                firstShownAt: firstShownAt,
                now: now,
                receipt: TrialReceipt.make(trialStartedAt: accessModel.trialStartedAt)
                    ?? debugPreview.receipt
            )
        }
#endif

        return resolve(
            status: accessModel.status,
            firstShownAt: accessModel.winbackOfferFirstShownAt,
            now: now,
            receipt: TrialReceipt.make(trialStartedAt: accessModel.trialStartedAt)
        )
    }
}
