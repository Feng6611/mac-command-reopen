import Foundation

enum ExternalLinks {
    static let officialURL = "https://commandreopen.com"
    static let githubURL = "https://github.com/Feng6611/mac-command-reopen"
    static let githubDocsBaseURL = "https://github.com/Feng6611/mac-command-reopen/blob/main"
    /// Where the free build is downloaded. The releases page, not the
    /// repository root: someone taking this route wants the app, not the
    /// source, and the root asks them to find the download themselves.
    static let freeBuildURL = "\(githubURL)/releases/latest"
    static let appStoreStandardEULAURL = "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"
    static let customTermsURL = "\(githubDocsBaseURL)/TERMS.md"
    static let privacyURL = "\(officialURL)/privacy/"
    static var termsURL: String {
        switch DistributionChannel.current {
        case .appStore:
            appStoreStandardEULAURL
        case .direct:
            customTermsURL
        }
    }
    static let contactEmailAddress = "fchen6611@gmail.com"
    static let contactEmail = "mailto:fchen6611@gmail.com"
    /// Feedback form for App Store users requesting a lifetime discount code.
    static let feedbackURL = "https://forms.gle/5MfTRHnmxivjqnrr5"
    /// Values come from `sale/brand/identity.md`, which is the single source
    /// for the developer identity across every asset — a buyer checking who
    /// wrote this should meet the same name here, on GitHub and on the site.
    static let developerName = "chenfeng"
    static let developerURL = "https://github.com/Feng6611"
    static let websiteDisplayName = "commandreopen.com"

    /// The repository name without its owner. Dropping `Feng6611/` evens out
    /// the About column and, more importantly, stops the pane introducing a
    /// fourth name for the same person — the row above already says who made
    /// this, and the account handle differs from that name.
    static let repositoryDisplayName = "mac-command-reopen"
}

enum AppStoreLinks {
    static let appID = "6757333924"
    static let productURL = "macappstore://apps.apple.com/app/id\(appID)"
    static let reviewURL = "macappstore://apps.apple.com/app/id\(appID)?action=write-review"
    static let manageSubscriptionsURL = "https://apps.apple.com/account/subscriptions"
}

enum DistributionChannel {
    case appStore
    case direct

    nonisolated(unsafe) static var current: Self {
#if DIRECT
        .direct
#elseif APPSTORE
        .appStore
#else
        .direct
#endif
    }
}
