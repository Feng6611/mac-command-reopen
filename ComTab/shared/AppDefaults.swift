//
//  AppDefaults.swift
//  ComTab
//
//  Created by Codex on 2026/4/29.
//

import Defaults
import Foundation

enum AppDefaults {
    enum RawKey {
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
}
