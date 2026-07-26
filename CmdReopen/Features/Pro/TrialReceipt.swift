//
//  TrialReceipt.swift
//  CmdReopen
//

import Foundation
import KikiCommerceCore

extension KikiAccessState {
    /// Whether a trial has actually run, so trial-scoped figures can be shown.
    ///
    /// `.notStarted` can still have a stored start date — a debug override
    /// forces that state, and it is the natural reading of a stale key — but a
    /// sheet inviting the user to begin a trial must not also report on one.
    var hasTrialHistory: Bool {
        switch self {
        case .trial, .expired: true
        case .notStarted, .pro: false
        }
    }
}

/// What the app actually did for this user during their trial.
///
/// The paywall at the end of the trial is the one place where the user is
/// already deciding whether to pay, so it argues from their own figures rather
/// than a generic claim. The count is the argument, so it belongs in the
/// paywall's stat card — the one component that renders a number as the focal
/// point — not in the subtitle, where it would be set smaller than the prices
/// it is meant to justify.
///
/// Below `minimumReopens` those same figures argue against buying, so the
/// receipt is withheld and the paywall keeps its generic copy.
struct TrialReceipt: Equatable {
    /// Fewer restores than this is too thin to lead with.
    static let minimumReopens = 5

    let reopenCount: Int

    /// The single app the user recognises fastest, which is what turns a
    /// statistic into their receipt. Rendered as its own stat beside the total.
    let leadApp: ReopenStatsStore.AppStat?

    init?(reopenCount: Int, leadApp: ReopenStatsStore.AppStat?) {
        guard reopenCount >= Self.minimumReopens else {
            return nil
        }
        self.reopenCount = reopenCount
        self.leadApp = leadApp
    }

    var formattedCount: String {
        reopenCount.formatted()
    }
}

extension TrialReceipt {
    /// Builds the receipt from the user's own trial window.
    ///
    /// Returns `nil` when the trial start is unknown, since the copy claims a
    /// trial-scoped number and lifetime totals would not be that.
    @MainActor
    static func make(
        statsStore: ReopenStatsStore? = nil,
        trialStartedAt: Date?
    ) -> TrialReceipt? {
        guard let trialStartedAt else {
            return nil
        }
        let statsStore = statsStore ?? .shared
        return TrialReceipt(
            reopenCount: statsStore.totalReopens(since: trialStartedAt),
            leadApp: statsStore.topApps(1, since: trialStartedAt).first
        )
    }
}
