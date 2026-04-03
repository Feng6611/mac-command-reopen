import Foundation

enum ExternalLinks {
    static let officialURL = "https://commandreopen.com"
    static let githubURL = "https://github.com/Feng6611/mac-command-reopen"
    static let githubDocsBaseURL = "https://github.com/Feng6611/mac-command-reopen/blob/main"
    static let termsURL = "\(githubDocsBaseURL)/TERMS.md"
    static let privacyURL = "\(githubDocsBaseURL)/PRIVACY.md"
    static let contactEmailAddress = "fchen6611@gmail.com"
    static let contactEmail = "mailto:fchen6611@gmail.com"
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
