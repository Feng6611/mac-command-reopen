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

/// Monitors `NSWorkspace.didActivateApplicationNotification` and relaunches
/// the frontmost (non-ComTab) application via `NSWorkspace.openApplication`.
final class ActivationMonitor: ObservableObject {
    private enum Constants {
        static let featureDefaultsKey = "com.comtab.autoHelpEnabled"
    }

    @Published var isFeatureEnabled: Bool {
        didSet {
            guard isFeatureEnabled != oldValue else { return }
            defaults.set(isFeatureEnabled, forKey: Constants.featureDefaultsKey)
            updateObservationState()
            AppLogger.activation.notice("Feature toggled to \(isFeatureEnabled ? "ON" : "OFF")")
        }
    }

    private let notificationCenter: NotificationCenter
    private let workspace: NSWorkspace
    private let defaults: UserDefaults
    private var activationObserver: NSObjectProtocol?

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
    }

    private func handleActivation(for app: NSRunningApplication) {
        guard app.bundleIdentifier != Bundle.main.bundleIdentifier else {
            AppLogger.activation.debug("Ignoring activation of ComTab itself.")
            return
        }
        guard let bundleID = app.bundleIdentifier else {
            AppLogger.activation.error("Activation without bundle identifier.")
            return
        }
        guard let appURL = workspace.urlForApplication(withBundleIdentifier: bundleID) else {
            AppLogger.activation.error("Unable to resolve URL for bundle id \(bundleID).")
            return
        }

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

    deinit {
        stopObserving()
    }
}
