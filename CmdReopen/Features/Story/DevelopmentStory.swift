//
//  DevelopmentStory.swift
//  CmdReopen
//

import AppKit
import Foundation

/// The developer's write-up of why Command Reopen exists, how it works without
/// permissions, and what it cannot do. It lives on kkuk.dev in two languages:
/// Chinese readers get the original, everyone else the English version.
enum DevelopmentStory {
    enum Source: String {
        /// The onboarding success step, under the zero-permissions card.
        case onboardingSuccess = "onboarding_success"
        /// A paywall opened outside onboarding.
        case paywall
        case about
    }

    enum Language: String {
        case english = "en"
        case chinese = "zh"
    }

    static let englishURL = "https://kkuk.dev/en/posts/command-reopen/"
    static let chineseURL = "https://kkuk.dev/posts/command-reopen/"

    static func language(for locale: Locale) -> Language {
        locale.language.languageCode == .chinese ? .chinese : .english
    }

    /// Campaign parameters name only the app and where the link sat — nothing
    /// about the person or their Mac.
    static func url(language: Language, source: Source) -> URL {
        let base = language == .chinese ? chineseURL : englishURL
        var components = URLComponents(string: base)!
        components.queryItems = [
            URLQueryItem(name: "utm_source", value: "command_reopen"),
            URLQueryItem(name: "utm_medium", value: "app"),
            URLQueryItem(name: "utm_campaign", value: "story"),
            URLQueryItem(name: "utm_content", value: source.rawValue)
        ]
        return components.url!
    }

    @MainActor
    static func open(from source: Source, locale: Locale? = nil) {
        let language = language(for: locale ?? AppLanguage.shared.locale)
        CommandReopenAnalytics.track(CommandReopenEvent.storyOpened(source: source, language: language))
        NSWorkspace.shared.open(url(language: language, source: source))
    }
}
