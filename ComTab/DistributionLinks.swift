import Foundation

enum ExternalLinks {
    static let officialURL = "https://commandreopen.com"
    static let githubURL = "https://github.com/Feng6611/mac-command-reopen"
    static let contactEmailAddress = "fchen6611@gmail.com"
    static let contactEmail = "mailto:fchen6611@gmail.com"
}

enum AppStoreLinks {
    static let appID = "6757333924"
    static let productURL = "macappstore://apps.apple.com/app/id\(appID)"
    static let reviewURL = "macappstore://apps.apple.com/app/id\(appID)?action=write-review"
}

enum DistributionChannel {
    case appStore
    case direct

    nonisolated(unsafe) static var current: Self {
#if DIRECT
        .direct
#else
        .appStore
#endif
    }
}
