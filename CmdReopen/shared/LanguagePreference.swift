import Combine
import Foundation
import SwiftUI

/// User-facing UI language chosen from Settings.
///
/// `.system` follows the macOS preferred language chain. Every other case
/// pins the app to a specific locale regardless of the system setting.
/// Case order defines the order shown in the Picker.
enum SupportedLanguage: String, CaseIterable, Identifiable {
    case system = ""
    case english = "en"
    case chinese = "zh-Hans"
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
        case .chinese:  "简体中文"
        case .japanese: "日本語"
        case .german:   "Deutsch"
        case .french:   "Français"
        }
    }
}

/// The app-owned, live localization service. Views receive its locale through
/// the SwiftUI environment; AppKit/Kiki callers resolve their String values
/// through `string(_:)` when they construct a menu or presentation model.
@MainActor
final class AppLanguage: ObservableObject {
    static let shared = AppLanguage()

    @Published var selected: SupportedLanguage {
        didSet {
            guard selected != oldValue else { return }
            defaults.set(selected.rawValue, forKey: Self.storageKey)
            clearLegacyLanguageOverride()
        }
    }

    var locale: Locale {
        selected == .system ? systemLocale : Locale(identifier: selected.rawValue)
    }

    private let defaults: UserDefaults
    private static let storageKey = AppDefaults.RawKey.preferredLanguage
    /// Versions before the live language service used this process-wide
    /// override and asked the user to restart. It shadows macOS's actual
    /// language even after the user selects "System", so it must never survive
    /// the migration.
    private static let legacyAppleLanguagesKey = "AppleLanguages"
    private static let globalDomainName = "NSGlobalDomain"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let raw = defaults.string(forKey: Self.storageKey) ?? ""
        self.selected = SupportedLanguage(rawValue: raw) ?? .system
        clearLegacyLanguageOverride()
    }

    func string(_ resource: LocalizedStringResource) -> String {
        var resource = resource
        resource.locale = locale
        return String(localized: resource)
    }

    func string(localized resource: LocalizedStringResource, comment: String? = nil) -> String {
        string(resource)
    }

    private func clearLegacyLanguageOverride() {
        defaults.removeObject(forKey: Self.legacyAppleLanguagesKey)
    }

    /// Do not ask `Locale.current` for this value. If a previous app version
    /// wrote `AppleLanguages`, Foundation can retain that process-local locale
    /// snapshot even after the preference is removed. The global domain is the
    /// authoritative macOS language chain and is unaffected by our app's old
    /// override.
    private var systemLocale: Locale {
        let globalDomain = defaults.persistentDomain(forName: Self.globalDomainName)
        let identifier = (globalDomain?[Self.legacyAppleLanguagesKey] as? [String])?.first
        return identifier.map(Locale.init(identifier:)) ?? .autoupdatingCurrent
    }
}
