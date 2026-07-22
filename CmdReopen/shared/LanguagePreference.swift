import Combine
import Foundation
import SwiftUI

/// User-facing UI language chosen from Settings.
///
/// `.system` follows the macOS preferred language chain. Every other case
/// pins the app to a specific locale regardless of the system setting.
/// Case order defines the order shown in the Picker.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system = ""
    case english = "en"
    case japanese = "ja"
    case german = "de"
    case french = "fr"

    var id: String { rawValue }

    /// Native-language label so the user recognizes each option in its own
    /// script. Never localize this — it is intentionally the source language
    /// on every locale, matching Apple's Language & Region UI convention.
    var displayName: String {
        switch self {
        case .system:   "System"
        case .english:  "English"
        case .japanese: "日本語"
        case .german:   "Deutsch"
        case .french:   "Français"
        }
    }
}

/// Persists the user's UI-language choice and mirrors it to CFBundle via
/// `AppleLanguages` so the next launch resolves resources in that language.
///
/// The change does not take effect until the app is relaunched — SwiftUI /
/// AppKit views composed against the current CFBundle resource chain do not
/// re-resolve mid-run. Callers should present a restart prompt after the
/// user picks a new language.
///
/// `.system` clears the override and lets macOS fall back to its normal
/// preferred-language chain. If none of the supported localizations match
/// the system chain, Bundle resolves to the development region (`en`).
@MainActor
final class LanguagePreference: ObservableObject {
    static let shared = LanguagePreference()

    @Published var selection: AppLanguage {
        didSet {
            guard selection != oldValue else { return }
            defaults.set(selection.rawValue, forKey: Self.storageKey)
            applyToAppleLanguages(selection)
        }
    }

    private let defaults: UserDefaults
    private static let storageKey = AppDefaults.RawKey.preferredLanguage
    private static let appleLanguagesKey = "AppleLanguages"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let raw = defaults.string(forKey: Self.storageKey) ?? ""
        self.selection = AppLanguage(rawValue: raw) ?? .system
    }

    private func applyToAppleLanguages(_ language: AppLanguage) {
        if language == .system {
            defaults.removeObject(forKey: Self.appleLanguagesKey)
        } else {
            defaults.set([language.rawValue], forKey: Self.appleLanguagesKey)
        }
    }
}
