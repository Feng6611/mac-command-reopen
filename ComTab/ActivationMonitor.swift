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
        static let reopenEvaluationDelay: TimeInterval = 0.12
        static let recentLaunchSuppressionInterval: TimeInterval = 0.9
        static let bundleDebounceInterval: TimeInterval = 0.1
        static let selfTriggerSuppressInterval: TimeInterval = 0.3
    }

    @Published var isFeatureEnabled: Bool {
        didSet {
            guard self.isFeatureEnabled != oldValue else { return }
            defaults.set(self.isFeatureEnabled, forKey: Constants.featureDefaultsKey)
            self.updateObservationState()
            AppLogger.activation.notice("Feature toggled to \(self.isFeatureEnabled ? "ON" : "OFF")")
        }
    }

    private let notificationCenter: NotificationCenter
    private let workspace: NSWorkspace
    private let defaults: UserDefaults
    private var activationObserver: NSObjectProtocol?
    private var lastReopenDates: [String: Date] = [:]
    private var selfTriggeredSuppressUntil: [String: Date] = [:]

    init(notificationCenter: NotificationCenter? = nil,
         workspace: NSWorkspace = .shared,
         defaults: UserDefaults = .standard) {
        self.workspace = workspace
        self.notificationCenter = notificationCenter ?? workspace.notificationCenter
        self.defaults = defaults
        defaults.register(defaults: [Constants.featureDefaultsKey: true])
        let storedValue = defaults.bool(forKey: Constants.featureDefaultsKey)
        _isFeatureEnabled = Published(initialValue: storedValue)
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

        // Hard filters for system apps that should never be reopened.
        if bundleID == "com.apple.dock" {
            AppLogger.activation.debug("Ignoring Dock activation.")
            return
        }
        if bundleID == "com.apple.finder" {
            AppLogger.activation.debug("Ignoring Finder activation.")
            return
        }

        if shouldIgnoreSelfTriggeredActivation(bundleID: bundleID) {
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
        guard let launchDate = app.launchDate else { return false }
        let elapsed = now.timeIntervalSince(launchDate)
        guard elapsed >= 0, elapsed <= Constants.recentLaunchSuppressionInterval else { return false }
        AppLogger.activation.debug("Skipping reopen for \(app.bundleIdentifier ?? "unknown"); launched \(elapsed)s ago.")
        return true
    }

    private func reopenApplication(withBundleIdentifier bundleID: String, at now: Date = Date()) {
        guard let appURL = workspace.urlForApplication(withBundleIdentifier: bundleID) else {
            AppLogger.activation.error("Unable to resolve URL for bundle id \(bundleID).")
            return
        }

        if let last = lastReopenDates[bundleID],
           now.timeIntervalSince(last) < Constants.bundleDebounceInterval {
            AppLogger.activation.debug("Skipping reopen for \(bundleID) due to debounce (\(now.timeIntervalSince(last))s elapsed).")
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
        if let until = selfTriggeredSuppressUntil[bundleID] {
            if Date() <= until {
                selfTriggeredSuppressUntil.removeValue(forKey: bundleID)
                AppLogger.activation.debug("Ignoring self-triggered activation for \(bundleID).")
                return true
            }
            selfTriggeredSuppressUntil.removeValue(forKey: bundleID)
        }
        return false
    }
}
