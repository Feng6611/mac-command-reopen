//
//  ActivationMonitor.swift
//  ComTab
//
//  Created by CHEN on 2025/10/31.
//

import AppKit
import Combine
import Foundation
import os

/// Monitors app activation and sends a reopen request when the user switches to an app
/// via Command+Tab (or other non-mouse activation), unless the app was recently launched.
final class ActivationMonitor: ObservableObject {
    private enum Constants {
        static let featureDefaultsKey = "com.comtab.autoHelpEnabled"
        static let excludedBundlesDefaultsKey = "com.comtab.excludedBundleIDs"
        static let reopenEvaluationDelay: TimeInterval = 0.2
        static let recentLaunchSuppressionInterval: TimeInterval = 0.9
        static let bundleDebounceInterval: TimeInterval = 0.1
        static let selfTriggerSuppressInterval: TimeInterval = 0.3
        static let rapidReturnSuppressionInterval: TimeInterval = 2.0
    }

    static let ignoredBundleIDs: Set<String> = [
        "com.apple.dock",
        "com.apple.finder",
        "com.apple.Spotlight",
        "com.apple.notificationcenterui",
        "com.apple.controlcenter",
        "com.apple.loginwindow",
        "com.apple.SecurityAgent",
        "com.apple.screencaptureui"
    ]

    @Published var isFeatureEnabled: Bool {
        didSet {
            guard self.isFeatureEnabled != oldValue else { return }
            defaults.set(self.isFeatureEnabled, forKey: Constants.featureDefaultsKey)
            self.updateObservationState()
            AppLogger.activation.notice("Feature toggled to \(self.isFeatureEnabled ? "ON" : "OFF")")
        }
    }

    @Published private(set) var userExcludedBundleIDs: Set<String> {
        didSet {
            guard userExcludedBundleIDs != oldValue else { return }
            defaults.set(Array(userExcludedBundleIDs).sorted(), forKey: Constants.excludedBundlesDefaultsKey)
            AppLogger.activation.notice("Updated user exclude list: \(self.userExcludedBundleIDs.count) bundle IDs")
        }
    }

    var sortedUserExcludedBundleIDs: [String] {
        userExcludedBundleIDs.sorted()
    }

    private let notificationCenter: NotificationCenter
    private let workspace: NSWorkspace
    private let defaults: UserDefaults
    private var activationObserver: NSObjectProtocol?
    private var lastReopenDates: [String: Date] = [:]
    private var selfTriggeredSuppressUntil: [String: Date] = [:]
    private var lastActivationDates: [String: Date] = [:]
    private var lastFrontmostBundleID: String?

    init(notificationCenter: NotificationCenter? = nil,
         workspace: NSWorkspace = .shared,
         defaults: UserDefaults = .standard) {
        self.workspace = workspace
        self.notificationCenter = notificationCenter ?? workspace.notificationCenter
        self.defaults = defaults
        defaults.register(defaults: [Constants.featureDefaultsKey: true])
        let storedValue = defaults.bool(forKey: Constants.featureDefaultsKey)
        let storedExcluded = defaults.stringArray(forKey: Constants.excludedBundlesDefaultsKey) ?? []
        _isFeatureEnabled = Published(initialValue: storedValue)
        _userExcludedBundleIDs = Published(initialValue: Set(storedExcluded))
        updateObservationState()
        AppLogger.activation.notice("ActivationMonitor ready. Feature enabled: \(storedValue)")
    }

    /// Attempt to relaunch the current frontmost application immediately.
    func relaunchFrontmostApplication() {
        guard isFeatureEnabled else {
            AppLogger.activation.info("Manual relaunch ignored because feature is disabled.")
            return
        }
        guard let app = workspace.frontmostApplication else {
            AppLogger.activation.error("No frontmost application to relaunch.")
            return
        }
        handleActivation(for: app)
    }

    func addExcludedBundleID(_ rawBundleID: String) {
        guard let normalized = Self.normalizeBundleID(rawBundleID) else { return }
        userExcludedBundleIDs.insert(normalized)
    }

    func removeExcludedBundleID(_ bundleID: String) {
        userExcludedBundleIDs.remove(bundleID)
    }

    private func updateObservationState() {
        if isFeatureEnabled {
            startObservingIfNeeded()
        } else {
            stopObserving()
        }
    }

    private func startObservingIfNeeded() {
        guard activationObserver == nil else { return }
        activationObserver = notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard
                let self,
                self.isFeatureEnabled,
                let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            else {
                return
            }
            self.handleActivation(for: app)
        }
        AppLogger.activation.notice("Started observing activation notifications.")
    }

    private func stopObserving() {
        if let activationObserver {
            notificationCenter.removeObserver(activationObserver)
            self.activationObserver = nil
            AppLogger.activation.notice("Stopped observing activation notifications.")
        }
        self.selfTriggeredSuppressUntil.removeAll()
    }

    private func handleActivation(for app: NSRunningApplication) {
        guard app.bundleIdentifier != Bundle.main.bundleIdentifier else {
            AppLogger.activation.debug("Ignoring activation of Command Reopen itself.")
            return
        }
        if NSEvent.pressedMouseButtons != 0 {
            AppLogger.activation.debug("Ignoring activation triggered by mouse interaction.")
            return
        }
        guard let bundleID = app.bundleIdentifier else {
            AppLogger.activation.error("Activation without bundle identifier.")
            return
        }

        let now = Date()
        let previousBundleID = lastFrontmostBundleID
        let previousBundleLastActivation = previousBundleID.flatMap { lastActivationDates[$0] }
        defer {
            lastActivationDates[bundleID] = now
            lastFrontmostBundleID = bundleID
        }

        if Self.isIgnoredBundleID(bundleID) {
            AppLogger.activation.debug("Ignoring activation for system bundle id \(bundleID).")
            return
        }

        if userExcludedBundleIDs.contains(bundleID) {
            AppLogger.activation.debug("Ignoring activation for user-excluded bundle id \(bundleID).")
            return
        }

        if shouldIgnoreSelfTriggeredActivation(bundleID: bundleID) {
            return
        }

        if Self.shouldSuppressRapidReturn(
            previousFrontmostBundleID: previousBundleID,
            targetBundleID: bundleID,
            targetLastActivationDate: lastActivationDates[bundleID],
            previousBundleLastActivationDate: previousBundleLastActivation,
            now: now,
            interval: Constants.rapidReturnSuppressionInterval
        ) {
            AppLogger.activation.debug("Skipping reopen for \(bundleID); rapid return heuristic matched.")
            return
        }

        scheduleReopenEvaluation(forBundleIdentifier: bundleID)
    }

    deinit {
        stopObserving()
    }

    private func scheduleReopenEvaluation(forBundleIdentifier bundleID: String) {
        AppLogger.activation.debug("Scheduled reopen evaluation for \(bundleID) in \(Constants.reopenEvaluationDelay)s.")
        DispatchQueue.main.asyncAfter(deadline: .now() + Constants.reopenEvaluationDelay) { [weak self] in
            guard let self else { return }
            guard self.isFeatureEnabled else {
                AppLogger.activation.info("Reopen evaluation ignored because feature is disabled.")
                return
            }
            guard let frontApp = self.workspace.frontmostApplication,
                  frontApp.bundleIdentifier == bundleID else {
                AppLogger.activation.debug("Reopen evaluation aborted; frontmost app changed.")
                return
            }

            let now = Date()
            if self.shouldSuppressRecentlyLaunchedReopen(for: frontApp, now: now) {
                return
            }

            self.reopenApplication(withBundleIdentifier: bundleID, at: now)
        }
    }

    private func shouldSuppressRecentlyLaunchedReopen(for app: NSRunningApplication, now: Date) -> Bool {
        guard Self.shouldSuppressRecentLaunch(
            launchDate: app.launchDate,
            now: now,
            interval: Constants.recentLaunchSuppressionInterval
        ) else {
            return false
        }
        let elapsed = now.timeIntervalSince(app.launchDate ?? now)
        AppLogger.activation.debug("Skipping reopen for \(app.bundleIdentifier ?? "unknown"); launched \(elapsed)s ago.")
        return true
    }

    private func reopenApplication(withBundleIdentifier bundleID: String, at now: Date = Date()) {
        guard let appURL = workspace.urlForApplication(withBundleIdentifier: bundleID) else {
            AppLogger.activation.error("Unable to resolve URL for bundle id \(bundleID).")
            return
        }

        if Self.shouldDebounceReopen(
            lastReopenDate: lastReopenDates[bundleID],
            now: now,
            interval: Constants.bundleDebounceInterval
        ) {
            let elapsed = now.timeIntervalSince(lastReopenDates[bundleID] ?? now)
            AppLogger.activation.debug("Skipping reopen for \(bundleID) due to debounce (\(elapsed)s elapsed).")
            return
        }
        lastReopenDates[bundleID] = now

        // Ignore one immediate echo activation caused by our own reopen request.
        selfTriggeredSuppressUntil[bundleID] = now.addingTimeInterval(Constants.selfTriggerSuppressInterval)

        AppLogger.activation.notice("Re-opening \(bundleID)")
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.createsNewApplicationInstance = false

        workspace.openApplication(at: appURL, configuration: configuration) { openedApp, error in
            if let error {
                AppLogger.activation.error("Failed to re-open \(bundleID): \(error.localizedDescription)")
            } else if let openedApp {
                AppLogger.activation.debug("Re-opened \(bundleID), pid \(openedApp.processIdentifier)")
            }
        }
    }

    private func shouldIgnoreSelfTriggeredActivation(bundleID: String) -> Bool {
        defer {
            selfTriggeredSuppressUntil.removeValue(forKey: bundleID)
        }
        if Self.shouldIgnoreSelfTriggered(until: selfTriggeredSuppressUntil[bundleID], now: Date()) {
            AppLogger.activation.debug("Ignoring self-triggered activation for \(bundleID).")
            return true
        }
        return false
    }

    static func isIgnoredBundleID(_ bundleID: String) -> Bool {
        ignoredBundleIDs.contains(bundleID)
    }

    static func normalizeBundleID(_ rawValue: String) -> String? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func shouldSuppressRecentLaunch(launchDate: Date?, now: Date, interval: TimeInterval) -> Bool {
        guard let launchDate else { return false }
        let elapsed = now.timeIntervalSince(launchDate)
        return elapsed >= 0 && elapsed <= interval
    }

    static func shouldDebounceReopen(lastReopenDate: Date?, now: Date, interval: TimeInterval) -> Bool {
        guard let lastReopenDate else { return false }
        return now.timeIntervalSince(lastReopenDate) < interval
    }

    static func shouldIgnoreSelfTriggered(until: Date?, now: Date) -> Bool {
        guard let until else { return false }
        return now <= until
    }

    static func shouldSuppressRapidReturn(
        previousFrontmostBundleID: String?,
        targetBundleID: String,
        targetLastActivationDate: Date?,
        previousBundleLastActivationDate: Date?,
        now: Date,
        interval: TimeInterval
    ) -> Bool {
        guard let previousFrontmostBundleID,
              previousFrontmostBundleID != targetBundleID,
              let targetLastActivationDate,
              let previousBundleLastActivationDate else {
            return false
        }
        let targetGap = now.timeIntervalSince(targetLastActivationDate)
        let previousGap = now.timeIntervalSince(previousBundleLastActivationDate)
        return targetGap >= 0 && targetGap < interval && previousGap >= 0 && previousGap < interval
    }
}
