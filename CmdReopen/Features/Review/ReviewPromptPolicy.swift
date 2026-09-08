import AppKit
import Foundation
import KikiReview
import StoreKit
import SwiftUI

protocol AppReviewPrompting {
    @MainActor
    func present(_ presentation: AppReviewPromptPresentation)
}

enum AppReviewPromptPresentation: Equatable {
    case custom
    case system
}

enum ReviewPromptTrigger: Equatable {
    /// A purchase is a high-confidence moment of customer satisfaction and
    /// does not require a reopen-count threshold.
    case purchaseCompleted
    case statsOpened
    case launchAtLoginEnabled
    case applicationLaunched

    fileprivate var requiresReopenHistory: Bool {
        self != .purchaseCompleted
    }
}

@MainActor
final class StoreKitAppReviewPrompter: AppReviewPrompting {
    private let customPromptController = KikiReviewPromptController()

    func present(_ presentation: AppReviewPromptPresentation) {
        switch presentation {
        case .custom:
            presentCustomPrompt()
        case .system:
            SKStoreReviewController.requestReview()
        }
    }

    private func presentCustomPrompt() {
        let language = AppLanguage.shared
        customPromptController.show(
            configuration: KikiReviewPromptConfiguration(
                windowTitle: language.string(localized: "Review Command Reopen",
                    comment: "Window title for Command Reopen's one-time custom review prompt."),
                title: language.string(localized: "Enjoying Command Reopen?",
                    comment: "Headline for Command Reopen's one-time custom review prompt."),
                message: language.string(localized: "If it’s made Cmd+Tab feel better, a quick App Store review helps more people find it.",
                    comment: "Body copy for Command Reopen's one-time custom review prompt."),
                primaryActionTitle: language.string(localized: "Rate on App Store",
                    comment: "Primary action in Command Reopen's one-time custom review prompt."),
                secondaryActionTitle: language.string(localized: "Not Now",
                    comment: "Dismiss action in Command Reopen's one-time custom review prompt.")
            ),
            tint: DS.Colors.brandPrimary
        ) { action in
            guard action == .review,
                  let url = URL(string: AppStoreLinks.reviewURL) else {
                return
            }
            NSWorkspace.shared.open(url)
        }
    }
}

/// Owns review presentation, per-launch throttling and persisted request history.
/// Reopen totals are supplied by the caller; this policy does not own statistics.
@MainActor
final class ReviewPromptPolicy {
    private enum ReviewPrompt {
        static let minimumSuccessfulReopens = 20
        static let maximumRequestsPerYear = 3
        static let rollingWindow: TimeInterval = 365 * 24 * 60 * 60
        static let requestTimestampsKey = "cmdreopenReviewPromptRequestTimestamps"
        static let migratedHistoryKey = "cmdreopenReviewPromptMigratedHistory"
        static let customPromptShownKey = "cmdreopenCustomReviewPromptShown"

        // Previous builds stored milestones rather than dates. Retain these
        // keys only to migrate their request count into the rolling cap.
        static let promptedMilestonesKey = "cmdreopenReviewPromptedReopenMilestones"
        static let legacyPromptedMilestonesKey = "comtabReviewPromptedReopenMilestones"
    }

    private let defaults: UserDefaults
    private let distributionChannel: DistributionChannel
    private let appReviewPrompter: any AppReviewPrompting
    private var hasRequestedReviewThisLaunch = false

    init(
        defaults: UserDefaults = .standard,
        distributionChannel: DistributionChannel = .current,
        appReviewPrompter: (any AppReviewPrompting)? = nil
    ) {
        self.defaults = defaults
        self.distributionChannel = distributionChannel
        self.appReviewPrompter = appReviewPrompter ?? StoreKitAppReviewPrompter()
    }

    /// Called during store initialization, after its snapshot migration, as before.
    func migrateLegacyHistoryIfNeeded() {
        Self.migrateArray(
            defaults: defaults,
            from: ReviewPrompt.legacyPromptedMilestonesKey,
            to: ReviewPrompt.promptedMilestonesKey
        )
        Self.migrateReviewPromptHistoryIfNeeded(defaults: defaults)
    }

    /// Requests an App Store review only at an intentional product moment.
    /// StoreKit may still decide not to show the system dialog.
    @discardableResult
    func requestReviewIfEligible(
        for trigger: ReviewPromptTrigger,
        totalSuccessfulReopens: Int,
        now: Date = Date()
    ) -> Bool {
        guard distributionChannel == .appStore,
              !hasRequestedReviewThisLaunch else {
            return false
        }

        if trigger.requiresReopenHistory,
           totalSuccessfulReopens <= ReviewPrompt.minimumSuccessfulReopens {
            return false
        }

        let cutoff = now.addingTimeInterval(-ReviewPrompt.rollingWindow).timeIntervalSince1970
        var requestTimestamps = (defaults.array(forKey: ReviewPrompt.requestTimestampsKey) as? [Double] ?? [])
            .filter { $0 > cutoff }

        guard requestTimestamps.count < ReviewPrompt.maximumRequestsPerYear else {
            defaults.set(requestTimestamps, forKey: ReviewPrompt.requestTimestampsKey)
            return false
        }

        requestTimestamps.append(now.timeIntervalSince1970)
        defaults.set(requestTimestamps, forKey: ReviewPrompt.requestTimestampsKey)
        hasRequestedReviewThisLaunch = true
        let presentation: AppReviewPromptPresentation
        if defaults.bool(forKey: ReviewPrompt.customPromptShownKey) {
            presentation = .system
        } else {
            // Persist at presentation time. Kiki reports which visible action
            // was chosen, but neither the app nor StoreKit can prove that a
            // person submitted a review.
            defaults.set(true, forKey: ReviewPrompt.customPromptShownKey)
            presentation = .custom
        }
        appReviewPrompter.present(presentation)
        return true
    }

#if DEBUG
    /// Exercises the production Kiki surface without consuming the one-time
    /// custom-prompt flag or an annual review-request slot.
    func presentCustomReviewPromptPreview() {
        appReviewPrompter.present(.custom)
    }
#endif

    private static func migrateArray(defaults: UserDefaults, from legacyKey: String, to currentKey: String) {
        guard defaults.object(forKey: currentKey) == nil,
              let legacyValue = defaults.array(forKey: legacyKey) else {
            return
        }

        defaults.set(legacyValue, forKey: currentKey)
        defaults.removeObject(forKey: legacyKey)
    }

    private static func migrateReviewPromptHistoryIfNeeded(defaults: UserDefaults) {
        guard !defaults.bool(forKey: ReviewPrompt.migratedHistoryKey) else {
            return
        }

        defer { defaults.set(true, forKey: ReviewPrompt.migratedHistoryKey) }

        guard defaults.object(forKey: ReviewPrompt.requestTimestampsKey) == nil else {
            return
        }

        let legacyRequestCount = min(
            ReviewPrompt.maximumRequestsPerYear,
            (defaults.array(forKey: ReviewPrompt.promptedMilestonesKey) as? [Int] ?? []).count
        )
        guard legacyRequestCount > 0 else {
            return
        }

        // The former implementation did not record dates. Treat its known
        // requests conservatively so this release cannot immediately exceed
        // Apple's rolling annual limit after upgrading.
        let timestamp = Date().timeIntervalSince1970
        defaults.set(
            Array(repeating: timestamp, count: legacyRequestCount),
            forKey: ReviewPrompt.requestTimestampsKey
        )
    }
}
