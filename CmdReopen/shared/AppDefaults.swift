//
//  AppDefaults.swift
//  CmdReopen
//
//  Created by Codex on 2026/4/29.
//

import Defaults
import Foundation

enum AppDefaults {
    enum RawKey {
        static let featureEnabled = "cmdreopenAutoHelpEnabled"
        static let excludedBundleIDs = "cmdreopenExcludedBundleIDs"
        static let defaultExcludedBundlesMigrated = "cmdreopenDefaultExcludedBundlesMigrated"
        static let trialStartDate = "cmdreopenTrialStartDate"
        static let hasSeenOnboarding = "cmdreopenHasSeenOnboarding"
    }

    enum LegacyRawKey {
        static let featureEnabled = "comtabAutoHelpEnabled"
        static let excludedBundleIDs = "comtabExcludedBundleIDs"
        static let defaultExcludedBundlesMigrated = "comtabDefaultExcludedBundlesMigrated"
        static let trialStartDate = "comtabTrialStartDate"
        static let hasSeenOnboarding = "comtabHasSeenOnboarding"
    }

    enum NamespacedLegacyRawKey {
        static let featureEnabled = "com.comtab.autoHelpEnabled"
        static let excludedBundleIDs = "com.comtab.excludedBundleIDs"
        static let defaultExcludedBundlesMigrated = "com.comtab.defaultExcludedBundlesMigrated"
        static let trialStartDate = "com.comtab.trialStartDate"
        static let hasSeenOnboarding = "com.comtab.hasSeenOnboarding"
    }

    static let featureEnabled = Defaults.Key<Bool>(RawKey.featureEnabled, default: true)
    static let excludedBundleIDs = Defaults.Key<[String]>(RawKey.excludedBundleIDs, default: [])
    static let defaultExcludedBundlesMigrated = Defaults.Key<Bool>(RawKey.defaultExcludedBundlesMigrated, default: false)
    static let trialStartDate = Defaults.Key<Date?>(RawKey.trialStartDate, default: nil)
    static let hasSeenOnboarding = Defaults.Key<Bool>(RawKey.hasSeenOnboarding, default: false)

    static func migrateLegacyKeys(in defaults: UserDefaults = .standard) {
        migrate(from: LegacyRawKey.featureEnabled, to: RawKey.featureEnabled, in: defaults)
        migrate(from: LegacyRawKey.excludedBundleIDs, to: RawKey.excludedBundleIDs, in: defaults)
        migrate(from: LegacyRawKey.defaultExcludedBundlesMigrated, to: RawKey.defaultExcludedBundlesMigrated, in: defaults)
        migrate(from: LegacyRawKey.trialStartDate, to: RawKey.trialStartDate, in: defaults)
        migrate(from: LegacyRawKey.hasSeenOnboarding, to: RawKey.hasSeenOnboarding, in: defaults)
        migrate(from: NamespacedLegacyRawKey.featureEnabled, to: RawKey.featureEnabled, in: defaults)
        migrate(from: NamespacedLegacyRawKey.excludedBundleIDs, to: RawKey.excludedBundleIDs, in: defaults)
        migrate(from: NamespacedLegacyRawKey.defaultExcludedBundlesMigrated, to: RawKey.defaultExcludedBundlesMigrated, in: defaults)
        migrate(from: NamespacedLegacyRawKey.trialStartDate, to: RawKey.trialStartDate, in: defaults)
        migrate(from: NamespacedLegacyRawKey.hasSeenOnboarding, to: RawKey.hasSeenOnboarding, in: defaults)
    }

    private static func migrate(from legacyKey: String, to currentKey: String, in defaults: UserDefaults) {
        guard let legacyValue = defaults.object(forKey: legacyKey) else {
            return
        }

        defaults.set(legacyValue, forKey: currentKey)
        defaults.removeObject(forKey: legacyKey)
    }
}
