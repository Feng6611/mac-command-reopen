//
//  AppDefaults.swift
//  ComTab
//
//  Created by Codex on 2026/4/29.
//

import Defaults
import Foundation

enum AppDefaults {
    static let featureEnabled = Defaults.Key<Bool>("com.comtab.autoHelpEnabled", default: true)
    static let excludedBundleIDs = Defaults.Key<[String]>("com.comtab.excludedBundleIDs", default: [])
    static let defaultExcludedBundlesMigrated = Defaults.Key<Bool>("com.comtab.defaultExcludedBundlesMigrated", default: false)
    static let trialStartDate = Defaults.Key<Date?>("com.comtab.trialStartDate", default: nil)
    static let hasSeenOnboarding = Defaults.Key<Bool>("com.comtab.hasSeenOnboarding", default: false)
}
