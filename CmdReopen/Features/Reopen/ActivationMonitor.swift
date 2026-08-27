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

struct ForegroundWindowObservationState: Equatable {
    private(set) var hasObservedVisibleWindow = false
    private(set) var consecutiveMissingSamples = 0

    mutating func observe(
        hasVisibleWindow: Bool,
        requiredMissingSamples: Int
    ) -> Bool {
        if hasVisibleWindow {
            hasObservedVisibleWindow = true
            consecutiveMissingSamples = 0
            return false
        }

        guard hasObservedVisibleWindow else {
            return false
        }

        consecutiveMissingSamples += 1
        guard consecutiveMissingSamples >= max(1, requiredMissingSamples) else {
            return false
        }

        reset()
        return true
    }

    mutating func reset() {
        hasObservedVisibleWindow = false
        consecutiveMissingSamples = 0
    }
}

/// Monitors app activation and sends a reopen request when the user switches to an app
/// via Command+Tab (or other non-mouse activation), unless the app was recently launched.
final class ActivationMonitor: ObservableObject {
    private enum Constants {
        static let reopenEvaluationDelay: TimeInterval = 0.2
        static let recentLaunchSuppressionInterval: TimeInterval = 0.9
        static let bundleDebounceInterval: TimeInterval = 0.1
        static let selfTriggerSuppressInterval: TimeInterval = 0.3
        static let rapidReturnSuppressionInterval: TimeInterval = 2.0
        static let foregroundWindowPollingInterval: TimeInterval = 0.15
        static let requiredMissingWindowSamples = 2
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
        "com.apple.finder",
        "com.apple.universalcontrol"
    ]

    private static let universalControlBundleID = "com.apple.universalcontrol"

    static let shared = ActivationMonitor()

    @Published var isFeatureEnabled: Bool {
        didSet {
            guard self.isFeatureEnabled != oldValue else { return }
            defaults[AppDefaults.featureEnabled] = self.isFeatureEnabled
            self.updateObservationState()
            AppLogger.activation.notice("Feature toggled to \(self.isFeatureEnabled ? "ON" : "OFF")")
        }
    }

    @Published var isAutomaticSwitcherReorderingEnabled: Bool {
        didSet {
            guard isAutomaticSwitcherReorderingEnabled != oldValue else { return }
            defaults[AppDefaults.automaticSwitcherReordering] = isAutomaticSwitcherReorderingEnabled
            updateForegroundWindowPollingState()
            AppLogger.activation.notice(
                "Automatic Cmd+Tab reordering toggled to \(self.isAutomaticSwitcherReorderingEnabled ? "ON" : "OFF")"
            )
        }
    }

    @Published private(set) var userExcludedBundleIDs: Set<String> {
        didSet {
            guard userExcludedBundleIDs != oldValue else { return }
            defaults[AppDefaults.excludedBundleIDs] = Array(userExcludedBundleIDs).sorted()
            AppLogger.activation.notice("Updated user exclude list: \(self.userExcludedBundleIDs.count) bundle IDs")
        }
    }

    /// Onboarding owns its own Cmd+Tab restore behavior. While it is visible,
    /// normal reopen requests for other apps must stay out of that interaction.
    private(set) var isReopenSuppressedForOnboarding = false

    var sortedUserExcludedBundleIDs: [String] {
        userExcludedBundleIDs.sorted()
    }

    private let notificationCenter: NotificationCenter
    private let workspace: NSWorkspace
    private let defaults: UserDefaults
    private let reopenStatsStore: ReopenStatsStore
    private let accessController: FeatureAvailabilityProviding
    private let windowInfoProvider: WindowInfoListing
    private let accessibilityWindowRestorer: AccessibilityWindowRestoring
    private let advancedWindowRestoreSettings: AdvancedWindowRestoreSettings
    private var activationObserver: NSObjectProtocol?
    private var foregroundWindowTimer: Timer?
    private var latestForegroundApplication: NSRunningApplication?
    private var monitoredForegroundApplication: NSRunningApplication?
    private var foregroundReturnTarget: NSRunningApplication?
    private var foregroundWindowObservation = ForegroundWindowObservationState()
    private var lastReopenDates: [String: Date] = [:]
    private var selfTriggeredSuppressUntil: [String: Date] = [:]
    private var lastActivationDates: [String: Date] = [:]
    private var lastFrontmostBundleID: String?
    private var pendingReopenEvaluation: DispatchWorkItem?
    private var pendingDockClickIntent: DockClickActivationIntent?

    init(notificationCenter: NotificationCenter? = nil,
         workspace: NSWorkspace = .shared,
         defaults: UserDefaults = .standard,
         reopenStatsStore: ReopenStatsStore? = nil,
         accessController: FeatureAvailabilityProviding? = nil,
         windowInfoProvider: WindowInfoListing = CoreGraphicsWindowInfoProvider(),
         accessibilityWindowRestorer: AccessibilityWindowRestoring = WindowRestorerFactory.makeDefault(),
         advancedWindowRestoreSettings: AdvancedWindowRestoreSettings = .shared) {
        AppDefaults.migrateLegacyKeys(in: defaults)
        self.workspace = workspace
        self.notificationCenter = notificationCenter ?? workspace.notificationCenter
        self.defaults = defaults
        self.reopenStatsStore = reopenStatsStore ?? .shared
        self.accessController = accessController ?? AppAccessController.shared
        self.windowInfoProvider = windowInfoProvider
        self.accessibilityWindowRestorer = accessibilityWindowRestorer
        self.advancedWindowRestoreSettings = advancedWindowRestoreSettings
        let storedValue = defaults[AppDefaults.featureEnabled]
        let storedAutomaticSwitcherReordering = defaults[AppDefaults.automaticSwitcherReordering]
        let storedExcluded = Set(defaults[AppDefaults.excludedBundleIDs])
        let hasStoredExcludedBundles = defaults.object(forKey: AppDefaults.RawKey.excludedBundleIDs) != nil
        let hasMigratedDefaultExcludedBundles = defaults[AppDefaults.defaultExcludedBundlesMigrated]
        let hasMigratedUniversalControlExclusion = defaults[AppDefaults.universalControlExcludedMigrated]
        var initialExcluded = hasStoredExcludedBundles ? storedExcluded : Self.defaultExcludedBundleIDs

        if !hasMigratedDefaultExcludedBundles {
            initialExcluded.formUnion(Self.defaultExcludedBundleIDs)
            defaults[AppDefaults.excludedBundleIDs] = Array(initialExcluded).sorted()
            defaults[AppDefaults.defaultExcludedBundlesMigrated] = true
        }

        if !hasMigratedUniversalControlExclusion {
            initialExcluded.insert(Self.universalControlBundleID)
            defaults[AppDefaults.excludedBundleIDs] = Array(initialExcluded).sorted()
            defaults[AppDefaults.universalControlExcludedMigrated] = true
        }

        _isFeatureEnabled = Published(initialValue: storedValue)
        _isAutomaticSwitcherReorderingEnabled = Published(initialValue: storedAutomaticSwitcherReordering)
        _userExcludedBundleIDs = Published(initialValue: initialExcluded)
        latestForegroundApplication = workspace.frontmostApplication
        configureForegroundObservation(for: workspace.frontmostApplication)
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

    func setOnboardingSessionActive(_ isActive: Bool) {
        guard isReopenSuppressedForOnboarding != isActive else { return }
        isReopenSuppressedForOnboarding = isActive
        if isActive {
            cancelPendingReopenEvaluation()
        }
        updateForegroundWindowPollingState()
        AppLogger.activation.debug(
            "External reopen requests \(isActive ? "suppressed" : "restored") for onboarding."
        )
    }

    private func updateObservationState() {
        if isFeatureEnabled {
            startObservingIfNeeded()
            updateForegroundWindowPollingState()
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
            // Window inspection is polling-based because other apps do not
            // publish close/minimize notifications. Keep that cost only while
            // the observed app is actually frontmost.
            self.updateForegroundWindowPollingState()
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
        cancelPendingReopenEvaluation()
        stopForegroundWindowPolling()
    }

    private static let lastExpiredNudgeDateKey = "lastExpiredPaywallNudgeDate"

    private func handleActivation(for app: NSRunningApplication) {
        guard !isReopenSuppressedForOnboarding else {
            AppLogger.activation.debug("Ignoring external activation while onboarding owns reopen behavior.")
            return
        }

        let shouldPresentExpiredNudge = !accessController.isCoreFeatureAvailable
        if shouldPresentExpiredNudge, !shouldShowExpiredNudge() {
            AppLogger.activation.debug("Ignoring activation; pro status not active.")
            return
        }
        guard app.bundleIdentifier != Bundle.main.bundleIdentifier else {
            AppLogger.activation.debug("Ignoring activation of Command Reopen itself.")
            return
        }
        if consumePendingDockClickIntent(for: app) {
            AppLogger.activation.debug("Confirmed Dock click owns the activation for \(app.bundleIdentifier ?? "unknown").")
            return
        }
        recordForegroundActivation(app)
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

        if HelperProcessFilter.isHelperLike(
            bundleID: bundleID,
            bundleURL: app.bundleURL,
            localizedName: app.localizedName,
            activationPolicy: app.activationPolicy
        ) {
            AppLogger.activation.debug("Ignoring activation for helper-like process \(bundleID).")
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

    private func recordForegroundActivation(_ app: NSRunningApplication) {
        guard Self.isEligibleForegroundApplication(app) else { return }

        let previousApplication = latestForegroundApplication
        latestForegroundApplication = app

        // Re-activating the same process (for example after closing Settings)
        // must not erase the return target learned when this app first became
        // frontmost.
        if monitoredForegroundApplication?.processIdentifier == app.processIdentifier {
            return
        }

        guard !userExcludedBundleIDs.contains(app.bundleIdentifier ?? "") else {
            monitoredForegroundApplication = nil
            foregroundReturnTarget = nil
            foregroundWindowObservation.reset()
            return
        }

        monitoredForegroundApplication = app
        foregroundReturnTarget = Self.isEligibleReturnTarget(previousApplication, excluding: app)
            ? previousApplication
            : Self.finderApplication(excluding: app)
        foregroundWindowObservation.reset()
    }

    private func configureForegroundObservation(for application: NSRunningApplication?) {
        guard let application, Self.isEligibleForegroundApplication(application) else {
            monitoredForegroundApplication = nil
            foregroundReturnTarget = nil
            return
        }
        monitoredForegroundApplication = userExcludedBundleIDs.contains(application.bundleIdentifier ?? "")
            ? nil
            : application
        foregroundReturnTarget = nil
        foregroundWindowObservation.reset()
    }

    private func updateForegroundWindowPollingState() {
        guard isFeatureEnabled,
              isAutomaticSwitcherReorderingEnabled,
              !isReopenSuppressedForOnboarding,
              let source = monitoredForegroundApplication,
              !userExcludedBundleIDs.contains(source.bundleIdentifier ?? ""),
              let frontmost = workspace.frontmostApplication,
              frontmost.processIdentifier == source.processIdentifier else {
            stopForegroundWindowPolling()
            return
        }
        startForegroundWindowPollingIfNeeded()
    }

    private func startForegroundWindowPollingIfNeeded() {
        guard foregroundWindowTimer == nil else { return }
        let timer = Timer(timeInterval: Constants.foregroundWindowPollingInterval, repeats: true) { [weak self] _ in
            self?.evaluateForegroundWindowDisappearance()
        }
        RunLoop.main.add(timer, forMode: .common)
        foregroundWindowTimer = timer
    }

    private func stopForegroundWindowPolling() {
        foregroundWindowTimer?.invalidate()
        foregroundWindowTimer = nil
        foregroundWindowObservation.reset()
    }

    private func evaluateForegroundWindowDisappearance() {
        guard accessController.isCoreFeatureAvailable,
              let source = monitoredForegroundApplication,
              !userExcludedBundleIDs.contains(source.bundleIdentifier ?? ""),
              let frontmost = workspace.frontmostApplication,
              frontmost.processIdentifier == source.processIdentifier,
              let windowInfoList = windowInfoProvider.onScreenWindowInfo() else {
            foregroundWindowObservation.reset()
            return
        }

        guard let returnTarget = resolvedForegroundReturnTarget(
            for: source,
            windowInfoList: windowInfoList
        ) else {
            foregroundWindowObservation.reset()
            return
        }

        let hasVisibleWindow = WindowInspector.hasVisibleWindow(
            ownerPID: source.processIdentifier,
            windowInfoList: windowInfoList
        )
        guard foregroundWindowObservation.observe(
            hasVisibleWindow: hasVisibleWindow,
            requiredMissingSamples: Constants.requiredMissingWindowSamples
        ) else {
            return
        }

        AppLogger.activation.notice(
            "Last visible window disappeared for \(source.bundleIdentifier ?? "unknown"); handing off foreground activation."
        )
        requestActivation(of: returnTarget, from: source)
    }

    private func resolvedForegroundReturnTarget(
        for source: NSRunningApplication,
        windowInfoList: [[String: Any]]
    ) -> NSRunningApplication? {
        if let foregroundReturnTarget,
           Self.isEligibleReturnTarget(foregroundReturnTarget, excluding: source),
           WindowInspector.hasVisibleWindow(
               ownerPID: foregroundReturnTarget.processIdentifier,
               windowInfoList: windowInfoList
           ) {
            return foregroundReturnTarget
        }
        return Self.finderApplication(excluding: source)
    }

    private func requestActivation(
        of target: NSRunningApplication,
        from source: NSRunningApplication
    ) {
        if #available(macOS 14.0, *), target.activate(from: source, options: []) {
            return
        }
        _ = target.activate(options: [.activateIgnoringOtherApps])
    }

    private static func finderApplication(excluding source: NSRunningApplication) -> NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder")
            .first(where: { isEligibleReturnTarget($0, excluding: source) })
    }

    private static func isEligibleForegroundApplication(_ app: NSRunningApplication) -> Bool {
        guard !app.isTerminated,
              app.activationPolicy == .regular,
              let bundleID = app.bundleIdentifier,
              bundleID != Bundle.main.bundleIdentifier,
              !isIgnoredBundleID(bundleID) else {
            return false
        }
        return !HelperProcessFilter.isHelperLike(
            bundleID: bundleID,
            bundleURL: app.bundleURL,
            localizedName: app.localizedName,
            activationPolicy: app.activationPolicy
        )
    }

    private static func isEligibleReturnTarget(
        _ app: NSRunningApplication?,
        excluding source: NSRunningApplication
    ) -> Bool {
        guard let app,
              app.processIdentifier != source.processIdentifier else {
            return false
        }
        return isEligibleForegroundApplication(app)
    }

    private func scheduleReopenEvaluation(
        forBundleIdentifier bundleID: String,
        presentsExpiredNudge: Bool
    ) {
        cancelPendingReopenEvaluation()
        let evaluation = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.isFeatureEnabled else {
                AppLogger.activation.info("Reopen evaluation ignored because feature is disabled.")
                return
            }
            guard !self.isReopenSuppressedForOnboarding else {
                AppLogger.activation.debug("Queued reopen evaluation ignored while onboarding is active.")
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

            if self.hasVisibleWindow(for: frontApp) {
                AppLogger.activation.debug("Skip reopen for \(bundleID): visible window found.")
                return
            }

            AppLogger.activation.info("Reopen needed for \(bundleID): no visible window found.")
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
#if APPSTORE
                self.presentExpiredPaywallNudge()
                AppLogger.activation.info("Trial expired nudge: allowing one-time reopen and showing paywall.")
#endif
            }
            self.reopenApplication(withBundleIdentifier: bundleID, at: now)
        }
        pendingReopenEvaluation = evaluation
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Constants.reopenEvaluationDelay,
            execute: evaluation
        )
    }

    private func cancelPendingReopenEvaluation() {
        pendingReopenEvaluation?.cancel()
        pendingReopenEvaluation = nil
    }

    private func shouldShowExpiredNudge(now: Date = Date()) -> Bool {
        let lastNudgeDate = defaults.object(forKey: Self.lastExpiredNudgeDateKey) as? Date
        return Self.shouldShowExpiredNudge(lastNudgeDate: lastNudgeDate, now: now)
    }

    private func recordExpiredNudge(at date: Date = Date()) {
        defaults.set(date, forKey: Self.lastExpiredNudgeDateKey)
    }

#if APPSTORE
    private func presentExpiredPaywallNudge() {
        Task { @MainActor in
            SettingsWindowController.shared.show(
                initialTab: .about,
                presentsPaywall: true
            )
        }
    }
#endif

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

    private func hasVisibleWindow(for app: NSRunningApplication) -> Bool {
        guard let windowInfoList = windowInfoProvider.onScreenWindowInfo() else {
            AppLogger.activation.error("Unable to inspect window list for \(app.bundleIdentifier ?? "unknown").")
            return false
        }

        return WindowInspector.hasVisibleWindow(
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

        let accessibilityResult = advancedWindowRestoreResult(for: bundleID)
        switch accessibilityResult {
        case .restored(let windowCount):
            let runningApplication = workspace.runningApplications.first {
                $0.bundleIdentifier == bundleID
            }
            _ = reopenStatsStore.recordSuccessfulReopen(
                bundleID: bundleID,
                localizedName: runningApplication?.localizedName,
                bundleURL: runningApplication?.bundleURL,
                activationPolicy: runningApplication?.activationPolicy
            )
            AppLogger.activation.notice(
                "Restored \(windowCount) window(s) for \(bundleID) through Accessibility."
            )
            return
        case .unavailable, .failed:
            if advancedWindowRestoreSettings.isAdvancedModeEnabled {
                AppLogger.activation.info("Accessibility restore unavailable for \(bundleID); using native reopen.")
            }
        }

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
                error: error,
                openedBundleURL: openedApp?.bundleURL,
                openedActivationPolicy: openedApp?.activationPolicy
            )
        }
    }

    private func advancedWindowRestoreResult(for bundleIdentifier: String) -> AccessibilityWindowRestoreResult {
#if DIRECT
        guard let mode = AdvancedWindowRestorePolicy.mode(
            isAdvancedModeEnabled: advancedWindowRestoreSettings.isAdvancedModeEnabled,
            restoresAllWindows: advancedWindowRestoreSettings.restoresAllWindows
        ) else { return .unavailable }
        return accessibilityWindowRestorer.restoreWindows(
            bundleIdentifier: bundleIdentifier,
            mode: mode
        )
#else
        return .unavailable
#endif
    }

    /// A global monitor passes only confirmed Dock AX hits here. Other mouse
    /// activations retain the normal activation path and never toggle windows.
    func cycleWindowsForConfirmedDockClick(
        bundleIdentifier: String,
        action: DockWindowCycleAction
    ) {
#if DIRECT
        guard isFeatureEnabled,
              accessController.isCoreFeatureAvailable,
              advancedWindowRestoreSettings.isAdvancedModeEnabled,
              advancedWindowRestoreSettings.cyclesWindowsFromDockClick,
              !userExcludedBundleIDs.contains(bundleIdentifier),
              !Self.isIgnoredBundleID(bundleIdentifier),
              bundleIdentifier != Bundle.main.bundleIdentifier else {
            return
        }
        let completedAction = accessibilityWindowRestorer.cycleWindows(
            bundleIdentifier: bundleIdentifier,
            action: action
        )
        guard completedAction != .none else { return }
        AppLogger.activation.notice("Dock AX click \(completedAction == .restoreAll ? "restored" : "minimized") all eligible windows for \(bundleIdentifier).")
#endif
    }

    func registerPendingDockClick(
        bundleIdentifier: String,
        processIdentifier: pid_t,
        at date: Date
    ) -> DockWindowCycleAction {
#if DIRECT
        guard isFeatureEnabled,
              accessController.isCoreFeatureAvailable,
              advancedWindowRestoreSettings.isAdvancedModeEnabled,
              advancedWindowRestoreSettings.cyclesWindowsFromDockClick,
              !userExcludedBundleIDs.contains(bundleIdentifier),
              !Self.isIgnoredBundleID(bundleIdentifier),
              bundleIdentifier != Bundle.main.bundleIdentifier else {
            pendingDockClickIntent = nil
            return .none
        }
        let action = accessibilityWindowRestorer.plannedCycleAction(bundleIdentifier: bundleIdentifier)
        guard action != .none else {
            pendingDockClickIntent = nil
            return .none
        }
        pendingDockClickIntent = DockClickActivationIntent(
            bundleIdentifier: bundleIdentifier,
            processIdentifier: processIdentifier,
            action: action,
            expiresAt: date.addingTimeInterval(1)
        )
        return action
#else
        return .none
#endif
    }

    private func consumePendingDockClickIntent(for application: NSRunningApplication) -> Bool {
#if DIRECT
        guard let intent = pendingDockClickIntent else { return false }
        defer { pendingDockClickIntent = nil }
        guard advancedWindowRestoreSettings.isAdvancedModeEnabled,
              advancedWindowRestoreSettings.cyclesWindowsFromDockClick else {
            return false
        }
        return intent.matches(
            bundleIdentifier: application.bundleIdentifier,
            processIdentifier: application.processIdentifier,
            now: Date()
        )
#else
        return false
#endif
    }

    func handleReopenCompletion(
        requestedBundleID: String,
        openedBundleID: String?,
        localizedName: String?,
        openedProcessIdentifier: pid_t?,
        error: Error?,
        openedBundleURL: URL? = nil,
        openedActivationPolicy: NSApplication.ActivationPolicy? = nil
    ) {
        if let error {
            AppLogger.activation.error("Failed to re-open \(requestedBundleID): \(error.localizedDescription)")
            return
        }

        let recordedBundleID = openedBundleID ?? requestedBundleID
        _ = reopenStatsStore.recordSuccessfulReopen(
            bundleID: recordedBundleID,
            localizedName: localizedName,
            bundleURL: openedBundleURL,
            activationPolicy: openedActivationPolicy
        )

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
