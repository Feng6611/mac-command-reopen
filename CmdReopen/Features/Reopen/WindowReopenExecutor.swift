import AppKit
import Foundation
import os

/// Executes restore requests and records successful requests, never individual windows.
/// Dock eligibility and foreground/MRU decisions remain owned by the app monitor.
final class WindowReopenExecutor {
    typealias NativeOpen = (URL, NSWorkspace.OpenConfiguration, @escaping (NSRunningApplication?, Error?) -> Void) -> Void

    private let workspace: NSWorkspace
    private let reopenStatsStore: ReopenStatsStore
    private let accessibilityWindowRestorer: AccessibilityWindowRestoring
    private let advancedWindowRestoreSettings: AdvancedWindowRestoreSettings
    private let resolveApplicationURL: (String) -> URL?
    private let openApplication: NativeOpen
    private static let bundleDebounceInterval: TimeInterval = 0.1
    private var lastReopenDates: [String: Date] = [:]

    init(
        workspace: NSWorkspace = .shared,
        reopenStatsStore: ReopenStatsStore,
        accessibilityWindowRestorer: AccessibilityWindowRestoring,
        advancedWindowRestoreSettings: AdvancedWindowRestoreSettings,
        resolveApplicationURL: ((String) -> URL?)? = nil,
        openApplication: NativeOpen? = nil
    ) {
        self.workspace = workspace
        self.reopenStatsStore = reopenStatsStore
        self.accessibilityWindowRestorer = accessibilityWindowRestorer
        self.advancedWindowRestoreSettings = advancedWindowRestoreSettings
        self.resolveApplicationURL = resolveApplicationURL ?? { workspace.urlForApplication(withBundleIdentifier: $0) }
        self.openApplication = openApplication ?? { url, configuration, completion in
            workspace.openApplication(at: url, configuration: configuration, completionHandler: completion)
        }
    }

    func reopenApplication(withBundleIdentifier bundleID: String, at now: Date, beforeNativeReopen: () -> Void) {
        guard let appURL = resolveApplicationURL(bundleID) else {
            AppLogger.activation.error("Unable to resolve URL for bundle id \(bundleID).")
            return
        }

        if ReopenPolicy.shouldDebounceReopen(
            lastReopenDate: lastReopenDates[bundleID],
            now: now,
            interval: Self.bundleDebounceInterval
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
        beforeNativeReopen()

        AppLogger.activation.notice("Re-opening \(bundleID). build=\(AppLogger.buildSignature)")
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.createsNewApplicationInstance = false

        openApplication(appURL, configuration) { [weak self] openedApp, error in
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
}
