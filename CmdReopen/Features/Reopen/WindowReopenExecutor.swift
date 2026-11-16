import AppKit
import Foundation
import os

/// Executes restore requests and counts only those followed by an observed window.
/// Dock eligibility and foreground/MRU decisions remain owned by the app monitor.
@MainActor
final class WindowReopenExecutor {
    typealias NativeOpen = (URL, NSWorkspace.OpenConfiguration, @escaping (NSRunningApplication?, Error?) -> Void) -> Void

    private let windowInfoProvider: WindowInfoListing
    private let waitForWindow: (Duration) async throws -> Void
    struct Result: Equatable {
        enum Outcome: String { case success, failed, unknown }
        enum Reason: String {
            case windowObserved = "window_observed", noWindowObserved = "no_window_observed"
            case requestError = "request_error", inspectionUnavailable = "inspection_unavailable"
            case processUnavailable = "process_unavailable", superseded, requestTimeout = "request_timeout"
            var outcome: Outcome {
                switch self {
                case .windowObserved: .success
                case .noWindowObserved, .requestError: .failed
                default: .unknown
                }
            }
        }
        let reason: Reason
        let durationMs: Int
        let dailyAttemptIndex: Int
        var outcome: Outcome { reason.outcome }
    }

    private struct Attempt {
        let id: UUID
        let startedAt = ContinuousClock.now
        let dailyIndex: Int
        var timeout: Task<Void, Never>?
    }
    private var pendingVerifications: [String: Attempt] = [:]
    private let defaults: UserDefaults
    private let calendar: Calendar
    private let wallClock: () -> Date
    private let requestTimeout: Duration
    var onResult: ((Result) -> Void)?
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
        openApplication: NativeOpen? = nil,
        windowInfoProvider: WindowInfoListing = CoreGraphicsWindowInfoProvider(),
        waitForWindow: @escaping (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        defaults: UserDefaults = .standard,
        calendar: Calendar = .current,
        wallClock: @escaping () -> Date = Date.init,
        requestTimeout: Duration = .seconds(5)
    ) {
        self.defaults = defaults
        self.calendar = calendar
        self.wallClock = wallClock
        self.requestTimeout = requestTimeout
        self.windowInfoProvider = windowInfoProvider
        self.waitForWindow = waitForWindow
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

        if let previous = pendingVerifications[bundleID] {
            finish(bundleID: bundleID, requestID: previous.id, reason: .superseded)
        }
        let requestID = UUID()
        let day = calendar.startOfDay(for: wallClock())
        let dayKey = "cmdreopen.analytics.reopenAttemptDay"
        let indexKey = "cmdreopen.analytics.reopenAttemptIndex"
        let dailyIndex = (defaults.object(forKey: dayKey) as? Date) == day
            ? defaults.integer(forKey: indexKey) + 1 : 1
        defaults.set(day, forKey: dayKey)
        defaults.set(dailyIndex, forKey: indexKey)
        pendingVerifications[bundleID] = Attempt(id: requestID, dailyIndex: dailyIndex)
        let timeout = requestTimeout
        pendingVerifications[bundleID]?.timeout = Task { [weak self] in
            do { try await Task.sleep(for: timeout) } catch { return }
            self?.finish(bundleID: bundleID, requestID: requestID, reason: .requestTimeout)
        }
        let accessibilityResult = advancedWindowRestoreResult(for: bundleID)
        switch accessibilityResult {
        case .restored:
            let runningApplication = workspace.runningApplications.first {
                $0.bundleIdentifier == bundleID
            }
            Task { [weak self] in
                await self?.handleReopenCompletion(
                    requestID: requestID, requestedBundleID: bundleID,
                    openedBundleID: runningApplication?.bundleIdentifier,
                    localizedName: runningApplication?.localizedName,
                    openedProcessIdentifier: runningApplication?.processIdentifier,
                    error: nil, openedBundleURL: runningApplication?.bundleURL,
                    openedActivationPolicy: runningApplication?.activationPolicy
                )
            }
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
            Task { @MainActor [weak self] in
                await self?.handleReopenCompletion(
                    requestID: requestID, requestedBundleID: bundleID,
                    openedBundleID: openedApp?.bundleIdentifier,
                    localizedName: openedApp?.localizedName,
                    openedProcessIdentifier: openedApp?.processIdentifier,
                    error: error, openedBundleURL: openedApp?.bundleURL,
                    openedActivationPolicy: openedApp?.activationPolicy
                )
            }
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

    private func handleReopenCompletion(
        requestID: UUID,
        requestedBundleID: String,
        openedBundleID: String?,
        localizedName: String?,
        openedProcessIdentifier: pid_t?,
        error: Error?,
        openedBundleURL: URL? = nil,
        openedActivationPolicy: NSApplication.ActivationPolicy? = nil
    ) async {
        guard pendingVerifications[requestedBundleID]?.id == requestID else { return }
        if let error {
            AppLogger.activation.error("Failed to re-open \(requestedBundleID): \(error.localizedDescription)")
            finish(bundleID: requestedBundleID, requestID: requestID, reason: .requestError)
            return
        }
        guard openedBundleID == nil || openedBundleID == requestedBundleID,
              let pid = openedProcessIdentifier else {
            finish(bundleID: requestedBundleID, requestID: requestID, reason: .processUnavailable)
            return
        }
        guard let reason = await observeWindow(ownerPID: pid, bundleID: requestedBundleID, requestID: requestID) else { return }
        guard pendingVerifications[requestedBundleID]?.id == requestID else { return }
        guard reason == .windowObserved else {
            finish(bundleID: requestedBundleID, requestID: requestID, reason: reason)
            return
        }
        let recordedBundleID = openedBundleID ?? requestedBundleID
        _ = reopenStatsStore.recordSuccessfulReopen(
            bundleID: recordedBundleID,
            localizedName: localizedName,
            bundleURL: openedBundleURL,
            activationPolicy: openedActivationPolicy
        )

        finish(bundleID: requestedBundleID, requestID: requestID, reason: .windowObserved)
    }

    private func finish(bundleID: String, requestID: UUID, reason: Result.Reason) {
        guard let attempt = pendingVerifications[bundleID], attempt.id == requestID else { return }
        pendingVerifications[bundleID] = nil
        attempt.timeout?.cancel()
        let elapsed = attempt.startedAt.duration(to: .now).components
        let milliseconds = max(0, Int(elapsed.seconds * 1_000 + elapsed.attoseconds / 1_000_000_000_000_000))
        let result = Result(reason: reason, durationMs: milliseconds, dailyAttemptIndex: attempt.dailyIndex)
        AppLogger.activation.info("Reopen result: \(result.outcome.rawValue, privacy: .public), \(reason.rawValue, privacy: .public), \(milliseconds)ms.")
        onResult?(result)
    }

    /// Bounded observation only: no extra open requests or permission prompts.
    /// Missing data and timeouts are unconfirmed, not native request failures.
    private func observeWindow(ownerPID: pid_t, bundleID: String, requestID: UUID) async -> Result.Reason? {
        var inspectionUnavailable = false
        // Sample immediately, then at roughly 0.3, 1 and 2 seconds.
        for delay in [Duration.zero, .milliseconds(300), .milliseconds(700), .seconds(1)] {
            if delay != .zero {
                do { try await waitForWindow(delay) } catch { return .inspectionUnavailable }
            }
            guard pendingVerifications[bundleID]?.id == requestID else { return nil }
            guard !Task.isCancelled else { return .inspectionUnavailable }
            guard let windows = windowInfoProvider.onScreenWindowInfo() else {
                inspectionUnavailable = true
                continue
            }
            if WindowInspector.hasVisibleWindow(ownerPID: ownerPID, windowInfoList: windows) {
                return .windowObserved
            }
        }
        return inspectionUnavailable ? .inspectionUnavailable : .noWindowObserved
    }

}
