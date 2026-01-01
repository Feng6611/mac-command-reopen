//
//  ActivationMonitor.swift
//  ComTab
//
//  Created by CHEN on 2025/10/31.
//

import AppKit
import Combine
import CoreGraphics
import Foundation
import os

/// Monitors `NSWorkspace.didActivateApplicationNotification` and relaunches
/// the frontmost (non-Command Reopen) application via `NSWorkspace.openApplication`.
final class ActivationMonitor: ObservableObject {
    private enum Constants {
        static let featureDefaultsKey = "com.comtab.autoHelpEnabled"
        static let finderSuppressionInterval: TimeInterval = 1.5
        static let finderEvaluationDelay: TimeInterval = 0.2
        static let desktopClearSuppressionInterval: TimeInterval = 2.0
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
    private var spaceChangeObserver: NSObjectProtocol?
    private var lastSpaceChangeDate: Date?
    private var lastDesktopClearDate: Date?
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

        if spaceChangeObserver == nil {
            spaceChangeObserver = notificationCenter.addObserver(
                forName: NSWorkspace.activeSpaceDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                let now = Date()
                self?.lastSpaceChangeDate = now
                AppLogger.activation.notice("Active Space changed at \(now.timeIntervalSince1970).")
            }
            AppLogger.activation.notice("Started observing Space change notifications.")
        }
    }

    private func stopObserving() {
        if let activationObserver {
            notificationCenter.removeObserver(activationObserver)
            self.activationObserver = nil
            AppLogger.activation.notice("Stopped observing activation notifications.")
        }
        if let spaceChangeObserver {
            notificationCenter.removeObserver(spaceChangeObserver)
            self.spaceChangeObserver = nil
            AppLogger.activation.notice("Stopped observing Space change notifications.")
        }
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

        // 硬过滤 Dock
        if bundleID == "com.apple.dock" {
            AppLogger.activation.debug("Ignoring Dock activation.")
            return
        }

        // 忽略一次因我们刚发起的 openApplication 导致的紧随其后激活
        if shouldIgnoreSelfTriggeredActivation(bundleID: bundleID) {
            return
        }

        if bundleID == "com.apple.finder" {
            handleFinderActivation(afterDelayFor: app)
            return
        }
        reopenApplication(withBundleIdentifier: bundleID)
    }

    deinit {
        stopObserving()
    }

    private func handleFinderActivation(afterDelayFor app: NSRunningApplication) {
        guard let bundleID = app.bundleIdentifier else {
            AppLogger.activation.error("Finder activation without bundle identifier.")
            return
        }
        let scheduledAt = Date()
        AppLogger.activation.debug("Finder activation deferred for \(Constants.finderEvaluationDelay)s evaluation.")
        DispatchQueue.main.asyncAfter(deadline: .now() + Constants.finderEvaluationDelay) { [weak self] in
            guard let self else { return }
            guard self.isFeatureEnabled else {
                AppLogger.activation.info("Finder evaluation ignored because feature is disabled.")
                return
            }
            let now = Date()
            if let currentApp = self.workspace.frontmostApplication,
               currentApp.bundleIdentifier != bundleID {
                AppLogger.activation.debug("Finder evaluation aborted; frontmost app changed to \(currentApp.bundleIdentifier ?? "nil").")
                return
            }
            AppLogger.activation.debug("Finder evaluation running \(now.timeIntervalSince(scheduledAt))s after activation.")
            self.captureDesktopClearStateIfNeeded()
            if self.shouldSuppressFinderActivation() {
                AppLogger.activation.notice("Finder activation suppressed.")
                return
            }
            self.reopenApplication(withBundleIdentifier: bundleID)
        }
    }

    private func shouldSuppressFinderActivation() -> Bool {
        let now = Date()
        if let desktopClearDate = lastDesktopClearDate {
            let elapsed = now.timeIntervalSince(desktopClearDate)
            if elapsed <= Constants.desktopClearSuppressionInterval {
                AppLogger.activation.debug("Finder suppression due to desktop clear (\(elapsed)s ago).")
                return true
            } else {
                AppLogger.activation.debug("Desktop clear suppression expired (\(elapsed)s ago).")
            }
        } else {
            AppLogger.activation.debug("No desktop clear timestamp recorded.")
        }

        if let lastSpaceChangeDate {
            let elapsed = now.timeIntervalSince(lastSpaceChangeDate)
            if elapsed <= Constants.finderSuppressionInterval {
                AppLogger.activation.debug("Finder suppression window active (\(elapsed)s since Space change).")
                return true
            } else {
                AppLogger.activation.debug("Finder suppression expired (\(elapsed)s since Space change).")
            }
        } else {
            AppLogger.activation.debug("No Space change timestamp recorded.")
        }

        return false
    }

    private func captureDesktopClearStateIfNeeded() {
        guard let windowListInfo = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            AppLogger.activation.error("Failed to obtain window list for desktop clear detection.")
            return
        }

        let hasVisibleNormalWindow = windowListInfo.contains { info in
            guard
                let layer = info[kCGWindowLayer as String] as? Int,
                let alpha = info[kCGWindowAlpha as String] as? Double,
                layer == 0,
                alpha > 0.01
            else {
                return false
            }
            guard let ownerName = info[kCGWindowOwnerName as String] as? String else {
                return false
            }
            let ignoredOwners: Set<String> = ["Dock", "Window Server"]
            return !ignoredOwners.contains(ownerName)
        }

        if !hasVisibleNormalWindow {
            lastDesktopClearDate = Date()
            AppLogger.activation.notice("Detected empty desktop; suppressing Finder for \(Constants.desktopClearSuppressionInterval)s.")
        }
    }

    private func reopenApplication(withBundleIdentifier bundleID: String) {
        guard let appURL = workspace.urlForApplication(withBundleIdentifier: bundleID) else {
            AppLogger.activation.error("Unable to resolve URL for bundle id \(bundleID).")
            return
        }

        let now = Date()
        if let last = lastReopenDates[bundleID],
           now.timeIntervalSince(last) < Constants.bundleDebounceInterval {
            AppLogger.activation.debug("Skipping reopen for \(bundleID) due to debounce (\(now.timeIntervalSince(last))s elapsed).")
            return
        }
        lastReopenDates[bundleID] = now

        // 标记一次性自触发抑制窗口
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
                // 消耗一次抑制
                selfTriggeredSuppressUntil.removeValue(forKey: bundleID)
                AppLogger.activation.debug("Ignoring self-triggered activation for \(bundleID).")
                return true
            } else {
                // 过期清理
                selfTriggeredSuppressUntil.removeValue(forKey: bundleID)
            }
        }
        return false
    }
}
