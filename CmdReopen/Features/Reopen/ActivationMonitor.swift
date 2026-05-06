//
//  ActivationMonitor.swift
//  CmdReopen
//
//  Created by CHEN on 2025/10/31.
//

import AppKit
import Combine
import Defaults
import Foundation
import os

/// Monitors app activation and sends a reopen request when the user switches to an app
/// via Command+Tab (or other non-mouse activation), unless the app was recently launched.
final class ActivationMonitor: ObservableObject {
    private enum Constants {
        static let reopenEvaluationDelay: TimeInterval = 0.2
        static let recentLaunchSuppressionInterval: TimeInterval = 0.9
        static let bundleDebounceInterval: TimeInterval = 0.1
        static let selfTriggerSuppressInterval: TimeInterval = 0.3
        static let rapidReturnSuppressionInterval: TimeInterval = 2.0
    }

    static let ignoredBundleIDs: Set<String> = [
        "com.apple.dock",
        "com.apple.Spotlight",
        "com.apple.notificationcenterui",
        "com.apple.controlcenter",
        "com.apple.loginwindow",
        "com.apple.SecurityAgent",
        "com.apple.screencaptureui"
    ]

    static let defaultExcludedBundleIDs: Set<String> = [
        "com.apple.finder"
    ]

    static let shared = ActivationMonitor()

    @Published var isFeatureEnabled: Bool {
        didSet {
            guard self.isFeatureEnabled != oldValue else { return }
            defaults[AppDefaults.featureEnabled] = self.isFeatureEnabled
            self.updateObservationState()
            AppLogger.activation.notice("Feature toggled to \(self.isFeatureEnabled ? "ON" : "OFF")")
        }
    }

    @Published private(set) var userExcludedBundleIDs: Set<String> {
        didSet {
            guard userExcludedBundleIDs != oldValue else { return }
            defaults[AppDefaults.excludedBundleIDs] = Array(userExcludedBundleIDs).sorted()
            AppLogger.activation.notice("Updated user exclude list: \(self.userExcludedBundleIDs.count) bundle IDs")
        }
    }

    var sortedUserExcludedBundleIDs: [String] {
        userExcludedBundleIDs.sorted()
    }

    private let notificationCenter: NotificationCenter
    private let workspace: NSWorkspace
    private let defaults: UserDefaults
    private let reopenStatsStore: ReopenStatsStore
    private let accessController: FeatureAvailabilityProviding
    private let windowInfoProvider: WindowInfoListing
    private var activationObserver: NSObjectProtocol?
    private var lastReopenDates: [String: Date] = [:]
    private var selfTriggeredSuppressUntil: [String: Date] = [:]
    private var lastActivationDates: [String: Date] = [:]
    private var lastFrontmostBundleID: String?

    init(notificationCenter: NotificationCenter? = nil,
         workspace: NSWorkspace = .shared,
         defaults: UserDefaults = .standard,
         reopenStatsStore: ReopenStatsStore? = nil,
         accessController: FeatureAvailabilityProviding? = nil,
         windowInfoProvider: WindowInfoListing = CoreGraphicsWindowInfoProvider()) {
        AppDefaults.migrateLegacyKeys(in: defaults)
        self.workspace = workspace
        self.notificationCenter = notificationCenter ?? workspace.notificationCenter
        self.defaults = defaults
        self.reopenStatsStore = reopenStatsStore ?? .shared
        self.accessController = accessController ?? AppAccessController.shared
        self.windowInfoProvider = windowInfoProvider
        let storedValue = defaults[AppDefaults.featureEnabled]
        let storedExcluded = Set(defaults[AppDefaults.excludedBundleIDs])
        let hasStoredExcludedBundles = defaults.object(forKey: AppDefaults.RawKey.excludedBundleIDs) != nil
        let hasMigratedDefaultExcludedBundles = defaults[AppDefaults.defaultExcludedBundlesMigrated]
        var initialExcluded = hasStoredExcludedBundles ? storedExcluded : Self.defaultExcludedBundleIDs

        if !hasMigratedDefaultExcludedBundles {
            initialExcluded.formUnion(Self.defaultExcludedBundleIDs)
            defaults[AppDefaults.excludedBundleIDs] = Array(initialExcluded).sorted()
            defaults[AppDefaults.defaultExcludedBundlesMigrated] = true
        }

        _isFeatureEnabled = Published(initialValue: storedValue)
        _userExcludedBundleIDs = Published(initialValue: initialExcluded)
        updateObservationState()
        AppLogger.activation.debug("ActivationMonitor ready. Feature enabled: \(storedValue)")
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
        AppLogger.activation.debug("Started observing activation notifications.")
    }

    private func stopObserving() {
        if let activationObserver {
            notificationCenter.removeObserver(activationObserver)
            self.activationObserver = nil
            AppLogger.activation.debug("Stopped observing activation notifications.")
        }
        self.selfTriggeredSuppressUntil.removeAll()
    }

    private static let lastExpiredNudgeDateKey = "lastExpiredPaywallNudgeDate"

    private func handleActivation(for app: NSRunningApplication) {
        let shouldPresentExpiredNudge = !accessController.isCoreFeatureAvailable
        if shouldPresentExpiredNudge, !shouldShowExpiredNudge() {
            AppLogger.activation.debug("Ignoring activation; pro status not active.")
            return
        }
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

        scheduleReopenEvaluation(
            forBundleIdentifier: bundleID,
            presentsExpiredNudge: shouldPresentExpiredNudge
        )
    }

    deinit {
        stopObserving()
    }

    private func scheduleReopenEvaluation(
        forBundleIdentifier bundleID: String,
        presentsExpiredNudge: Bool
    ) {
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

            let report = self.visibleWindowReport(for: frontApp)
            if report.hasVisibleWindow {
                AppLogger.activation.notice(
                    """
                    Skip reopen for \(bundleID): visibleWindow=true total=\(report.totalWindowsForApp) \
                    onScreen=\(report.onScreenWindows) candidates=\(report.visibleCandidateWindows)
                    """
                )
                return
            }

            AppLogger.activation.notice(
                """
                Reopen needed for \(bundleID): visibleWindow=false total=\(report.totalWindowsForApp) \
                onScreen=\(report.onScreenWindows) candidates=\(report.visibleCandidateWindows)
                """
            )
            if presentsExpiredNudge {
                guard !self.accessController.isCoreFeatureAvailable else {
                    self.reopenApplication(withBundleIdentifier: bundleID, at: now)
                    return
                }
                guard self.shouldShowExpiredNudge(now: now) else {
                    AppLogger.activation.debug("Skipping expired nudge reopen; today's nudge was already recorded.")
                    return
                }
                self.recordExpiredNudge(at: now)
                self.presentExpiredPaywallNudge()
                AppLogger.activation.info("Trial expired nudge: allowing one-time reopen and showing paywall.")
            }
            self.reopenApplication(withBundleIdentifier: bundleID, at: now)
        }
    }

    private func shouldShowExpiredNudge(now: Date = Date()) -> Bool {
        let lastNudgeDate = defaults.object(forKey: Self.lastExpiredNudgeDateKey) as? Date
        return Self.shouldShowExpiredNudge(lastNudgeDate: lastNudgeDate, now: now)
    }

    private func recordExpiredNudge(at date: Date = Date()) {
        defaults.set(date, forKey: Self.lastExpiredNudgeDateKey)
    }

    private func presentExpiredPaywallNudge() {
        Task { @MainActor in
            SettingsWindowController.shared.show(
                initialTab: .about,
                presentsPaywall: true
            )
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

    private func visibleWindowReport(for app: NSRunningApplication) -> WindowInspectionReport {
        guard let windowInfoList = windowInfoProvider.onScreenWindowInfo() else {
            AppLogger.activation.error("Unable to inspect window list for \(app.bundleIdentifier ?? "unknown").")
            return WindowInspectionReport(
                hasVisibleWindow: false,
                totalWindowsForApp: 0,
                onScreenWindows: 0,
                visibleCandidateWindows: 0,
                transparentWindows: 0,
                nonStandardLayerWindows: 0,
                tinyWindows: 0
            )
        }

        return WindowInspector.visibleWindowReport(
            ownerPID: app.processIdentifier,
            windowInfoList: windowInfoList
        )
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

        AppLogger.activation.notice("Re-opening \(bundleID). build=\(AppLogger.buildSignature)")
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.createsNewApplicationInstance = false

        workspace.openApplication(at: appURL, configuration: configuration) { [weak self] openedApp, error in
            self?.handleReopenCompletion(
                requestedBundleID: bundleID,
                openedBundleID: openedApp?.bundleIdentifier,
                localizedName: openedApp?.localizedName,
                openedProcessIdentifier: openedApp?.processIdentifier,
                error: error
            )
        }
    }

    func handleReopenCompletion(
        requestedBundleID: String,
        openedBundleID: String?,
        localizedName: String?,
        openedProcessIdentifier: pid_t?,
        error: Error?
    ) {
        if let error {
            AppLogger.activation.error("Failed to re-open \(requestedBundleID): \(error.localizedDescription)")
            return
        }

        let recordedBundleID = openedBundleID ?? requestedBundleID
        Task { @MainActor [reopenStatsStore] in
            reopenStatsStore.recordSuccessfulReopen(
                bundleID: recordedBundleID,
                localizedName: localizedName
            )
        }

        if let openedProcessIdentifier {
            AppLogger.activation.debug("Re-opened \(recordedBundleID), pid \(openedProcessIdentifier)")
        } else {
            AppLogger.activation.debug("Re-opened \(recordedBundleID)")
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

    static func shouldShowExpiredNudge(
        lastNudgeDate: Date?,
        now: Date,
        calendar: Calendar = .current
    ) -> Bool {
        guard let lastNudgeDate else { return true }
        return !calendar.isDate(lastNudgeDate, inSameDayAs: now)
    }

    static func hasVisibleWindow(
        ownerPID: pid_t,
        windowInfoList: [[String: Any]],
        minimumDimension: CGFloat = 0
    ) -> Bool {
        WindowInspector.hasVisibleWindow(
            ownerPID: ownerPID,
            windowInfoList: windowInfoList,
            minimumDimension: minimumDimension
        )
    }

    static func windowOwnerPID(from windowInfo: [String: Any]) -> pid_t? {
        WindowInspector.windowOwnerPID(from: windowInfo)
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
