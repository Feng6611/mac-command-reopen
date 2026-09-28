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
    case custom(ReviewPromptContent)
    case system
}

/// What the one-time custom prompt says, taken from the user's own history.
///
/// A generic "Enjoying the app?" is easy to wave away and invites a rating
/// of the mood rather than the product. The count is what this app has
/// actually done for this person, so the request argues from that instead.
struct ReviewPromptContent: Equatable {
    enum Moment: Equatable {
        /// Right after a purchase: thank first, then ask.
        case purchase
        /// While the user is looking at what the app has done.
        case usage
    }

    let moment: Moment
    let reopenCount: Int
    /// The app whose windows came back most often, when there is one.
    let leadAppName: String?
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

    /// Whether this moment may spend the one-time custom prompt.
    ///
    /// Only moments the user started inside the app qualify: a purchase they
    /// just finished, or the Statistics pane they just opened. A launch — often
    /// a login-item launch while the user is typing elsewhere — or a toggle in
    /// onboarding is not a moment to open a window that takes focus and
    /// answers Return, so those fall back to StoreKit's own prompt.
    fileprivate var allowsCustomPrompt: Bool {
        switch self {
        case .purchaseCompleted, .statsOpened: true
        case .launchAtLoginEnabled, .applicationLaunched: false
        }
    }
}

@MainActor
final class StoreKitAppReviewPrompter: AppReviewPrompting {
    private let customPromptController = KikiReviewPromptController()

    func present(_ presentation: AppReviewPromptPresentation) {
        switch presentation {
        case .custom(let content):
            presentCustomPrompt(content)
        case .system:
            SKStoreReviewController.requestReview()
        }
    }

    private func presentCustomPrompt(_ content: ReviewPromptContent) {
        let language = AppLanguage.shared
        customPromptController.show(
            configuration: KikiReviewPromptConfiguration(
                windowTitle: language.string(localized: "Review Command Reopen",
                    comment: "Window title for Command Reopen's one-time custom review prompt."),
                title: Self.title(for: content, language: language),
                message: Self.message(for: content, language: language),
                primaryActionTitle: language.string(localized: "Write a Review",
                    comment: "Primary action in Command Reopen's one-time custom review prompt; opens the App Store's write-review page."),
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

    static func title(for content: ReviewPromptContent, language: AppLanguage) -> String {
        switch content.moment {
        case .purchase:
            return language.string(localized: "Thanks for buying Command Reopen",
                comment: "Headline of the review prompt shown right after a purchase.")
        case .usage:
            return language.string(localized: "\(content.reopenCount) windows brought back",
                comment: "Headline of the review prompt: how many windows Command Reopen has restored for this user. Plural-aware.")
        }
    }

    static func message(for content: ReviewPromptContent, language: AppLanguage) -> String {
        let ask = language.string(localized: "If it has saved you some Cmd+Tab hassle, a short App Store review helps others with the same problem find it.",
            comment: "The request in Command Reopen's review prompt. Must not ask for a rating or a positive review.")

        switch content.moment {
        case .purchase where content.reopenCount > 0:
            let count = language.string(localized: "It has brought back \(content.reopenCount) windows so far.",
                comment: "Review prompt after a purchase: windows restored for this user so far. Plural-aware.")
            return Self.join(count, ask, language: language)
        case .usage:
            guard let leadAppName = content.leadAppName else { return ask }
            let lead = language.string(localized: "Most of them were in \(leadAppName).",
                comment: "Review prompt: the app whose windows were restored most often. %@ is an app name.")
            return Self.join(lead, ask, language: language)
        case .purchase:
            return ask
        }
    }

    /// Joins two localized sentences. Chinese and Japanese sentences end in a
    /// full-width stop and take no space after it.
    private static func join(_ first: String, _ second: String, language: AppLanguage) -> String {
        let code = language.locale.language.languageCode?.identifier
        let separator = (code == "zh" || code == "ja") ? "" : " "
        return first + separator + second
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
    private let isAudienceEligible: @MainActor () -> Bool
    private var hasRequestedReviewThisLaunch = false

    /// - Parameter isAudienceEligible: whether the app is working for this user
    ///   right now. An expired trial has switched the feature off and has just
    ///   been shown a paywall; asking that user for a review invites a rating
    ///   of the price rather than the product.
    init(
        defaults: UserDefaults = .standard,
        distributionChannel: DistributionChannel = .current,
        appReviewPrompter: (any AppReviewPrompting)? = nil,
        isAudienceEligible: @escaping @MainActor () -> Bool = { true }
    ) {
        self.defaults = defaults
        self.distributionChannel = distributionChannel
        self.appReviewPrompter = appReviewPrompter ?? StoreKitAppReviewPrompter()
        self.isAudienceEligible = isAudienceEligible
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
        leadAppName: String? = nil,
        now: Date = Date()
    ) -> Bool {
        guard distributionChannel == .appStore,
              !hasRequestedReviewThisLaunch,
              isAudienceEligible() else {
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
        if trigger.allowsCustomPrompt,
           !defaults.bool(forKey: ReviewPrompt.customPromptShownKey) {
            // Persist at presentation time. Kiki reports which visible action
            // was chosen, but neither the app nor StoreKit can prove that a
            // person submitted a review.
            defaults.set(true, forKey: ReviewPrompt.customPromptShownKey)
            presentation = .custom(ReviewPromptContent(
                moment: trigger == .purchaseCompleted ? .purchase : .usage,
                reopenCount: totalSuccessfulReopens,
                leadAppName: leadAppName
            ))
        } else {
            presentation = .system
        }
        appReviewPrompter.present(presentation)
        return true
    }

#if DEBUG
    /// Exercises the production Kiki surface without consuming the one-time
    /// custom-prompt flag or an annual review-request slot.
    func presentCustomReviewPromptPreview(totalSuccessfulReopens: Int, leadAppName: String?) {
        appReviewPrompter.present(.custom(ReviewPromptContent(
            moment: .usage,
            // A fresh development install has no history; show a
            // representative count rather than a prompt that reads "0".
            reopenCount: totalSuccessfulReopens > 0 ? totalSuccessfulReopens : 143,
            leadAppName: totalSuccessfulReopens > 0 ? leadAppName : "Xcode"
        )))
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
