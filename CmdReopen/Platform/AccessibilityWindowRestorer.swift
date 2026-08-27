//
//  AccessibilityWindowRestorer.swift
//  CmdReopen
//
//  Direct-only advanced window behavior. The product owns the restore policy;
//  this seam owns the narrow Accessibility API calls that enact it.
//

import Foundation
#if DIRECT
import AppKit
import ApplicationServices
import os
#endif

enum AccessibilityWindowRestoreMode: Equatable {
    case focusedWindow
    case allMinimizedWindows
}

enum AccessibilityWindowRestoreResult: Equatable {
    case restored(windowCount: Int)
    case unavailable
    case failed
}

enum DockWindowCycleAction: Equatable {
    case restoreAll
    case minimizeAll
    case none
}

enum DockWindowCyclePlanner {
    /// Preserve native Dock activation for background apps that already expose
    /// a visible window. Window cycling begins only after the app is frontmost,
    /// or when a background app has no visible window to activate.
    static func action(
        forMinimizedStates minimizedStates: [Bool],
        targetWasFrontmost: Bool
    ) -> DockWindowCycleAction {
        guard !minimizedStates.isEmpty else { return .none }
        if minimizedStates.allSatisfy({ $0 }) { return .restoreAll }
        return targetWasFrontmost ? .minimizeAll : .none
    }

    static func didComplete(
        action: DockWindowCycleAction,
        finalMinimizedStates: [Bool?]
    ) -> Bool {
        guard !finalMinimizedStates.isEmpty,
              finalMinimizedStates.allSatisfy({ $0 != nil }) else {
            return false
        }
        switch action {
        case .restoreAll:
            return finalMinimizedStates.allSatisfy { $0 == false }
        case .minimizeAll:
            return finalMinimizedStates.allSatisfy { $0 == true }
        case .none:
            return false
        }
    }

    static func shouldActivateApplication(for action: DockWindowCycleAction) -> Bool {
        action == .restoreAll
    }
}

enum DockClickExecutionTiming {
    static func delay(
        for action: DockWindowCycleAction,
        targetWasFrontmost: Bool
    ) -> TimeInterval {
        switch action {
        case .restoreAll, .none:
            return 0.15
        case .minimizeAll:
            // Foreground minimize is responsive. Retain a defensive longer
            // delay if a future policy ever permits minimize during activation.
            return targetWasFrontmost ? 0.15 : 0.75
        }
    }
}

enum DockAccessibilityHitTest {
    /// AX hit testing uses top-left-relative Quartz screen coordinates. Never
    /// pass AppKit's bottom-left-relative global location into this API.
    static func accessibilityPoint(
        quartzLocation: CGPoint?,
        appKitLocation _: CGPoint
    ) -> CGPoint? {
        quartzLocation
    }

    static func isDockItem(role: String?) -> Bool {
        role == "AXDockItem"
    }

    static func bundleIdentifier(from url: URL?) -> String? {
        guard let url,
              url.isFileURL,
              url.pathExtension == "app",
              let bundle = Bundle(url: url),
              let identifier = bundle.bundleIdentifier,
              !identifier.isEmpty else {
            return nil
        }
        return identifier
    }
}

struct DockClickActivationIntent: Equatable {
    let bundleIdentifier: String
    let processIdentifier: pid_t
    let action: DockWindowCycleAction
    let targetWasFrontmost: Bool
    let expiresAt: Date

    func matches(bundleIdentifier: String?, processIdentifier: pid_t, now: Date) -> Bool {
        now <= expiresAt && self.bundleIdentifier == bundleIdentifier && self.processIdentifier == processIdentifier
    }
}

final class DockClickIntentCoordinator {
    static let shared = DockClickIntentCoordinator()

    private let lock = NSLock()
    private var pendingIntent: DockClickActivationIntent?

    func register(_ intent: DockClickActivationIntent) {
        lock.lock()
        pendingIntent = intent
        lock.unlock()
    }

    func intent(
        matchingBundleIdentifier bundleIdentifier: String?,
        processIdentifier: pid_t,
        now: Date
    ) -> DockClickActivationIntent? {
        lock.lock()
        defer { lock.unlock() }
        guard let intent = pendingIntent else { return nil }
        guard intent.matches(
            bundleIdentifier: bundleIdentifier,
            processIdentifier: processIdentifier,
            now: now
        ) else {
            pendingIntent = nil
            return nil
        }
        return intent
    }

    func isCurrent(_ intent: DockClickActivationIntent, now: Date) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let pendingIntent else { return false }
        guard now <= pendingIntent.expiresAt else {
            self.pendingIntent = nil
            return false
        }
        return pendingIntent == intent
    }

    func consume(_ intent: DockClickActivationIntent, now: Date) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let pendingIntent,
              now <= pendingIntent.expiresAt,
              pendingIntent == intent else {
            if (self.pendingIntent?.expiresAt ?? .distantFuture) < now {
                self.pendingIntent = nil
            }
            return false
        }
        self.pendingIntent = nil
        return true
    }

    func clear() {
        lock.lock()
        pendingIntent = nil
        lock.unlock()
    }
}

enum AdvancedWindowRestorePolicy {
    static func mode(isAdvancedModeEnabled: Bool, restoresAllWindows: Bool) -> AccessibilityWindowRestoreMode? {
        guard isAdvancedModeEnabled else { return nil }
        return restoresAllWindows ? .allMinimizedWindows : .focusedWindow
    }
}

enum AccessibilityWindowFocusPlanner {
    static func preferredIndex(focused: [Bool], main: [Bool]) -> Int? {
        guard focused.count == main.count, !focused.isEmpty else { return nil }
        if let focusedIndex = focused.firstIndex(of: true) { return focusedIndex }
        if let mainIndex = main.firstIndex(of: true) { return mainIndex }
        return focused.indices.first
    }
}

enum AccessibilityWindowCandidatePlanner {
    static func minimized<Element>(
        from elements: [Element],
        state: (Element) -> Bool?
    ) -> [Element] {
        elements.filter { state($0) == true }
    }
}

protocol AccessibilityWindowRestoring: AnyObject {
    func restoreWindows(
        bundleIdentifier: String,
        mode: AccessibilityWindowRestoreMode
    ) -> AccessibilityWindowRestoreResult

    func plannedCycleAction(
        bundleIdentifier: String,
        targetWasFrontmost: Bool
    ) -> DockWindowCycleAction

    func cycleWindows(
        bundleIdentifier: String,
        action: DockWindowCycleAction
    ) -> DockWindowCycleAction
}

#if DIRECT
final class AccessibilityWindowRestorer: AccessibilityWindowRestoring {
    func restoreWindows(
        bundleIdentifier: String,
        mode: AccessibilityWindowRestoreMode
    ) -> AccessibilityWindowRestoreResult {
        guard AXIsProcessTrusted() else { return .unavailable }
        guard let application = runningApplication(for: bundleIdentifier) else { return .failed }

        let windows = windows(for: application.processIdentifier)
        guard !windows.isEmpty else { return .failed }

        let targets: [AXUIElement]
        let minimizedWindows = AccessibilityWindowCandidatePlanner.minimized(
            from: windows,
            state: minimizedState(_:)
        )
        switch mode {
        case .focusedWindow:
            targets = preferredWindow(
                from: minimizedWindows,
                processIdentifier: application.processIdentifier
            ).map { [$0] } ?? []
        case .allMinimizedWindows:
            targets = minimizedWindows
        }
        guard !targets.isEmpty else { return .failed }

        _ = application.activate(options: [.activateIgnoringOtherApps])
        var restoredCount = 0
        for window in targets where restoreAndRaise(window) {
            restoredCount += 1
        }
        return restoredCount > 0 ? .restored(windowCount: restoredCount) : .failed
    }

    func plannedCycleAction(
        bundleIdentifier: String,
        targetWasFrontmost: Bool
    ) -> DockWindowCycleAction {
        guard AXIsProcessTrusted(), let application = runningApplication(for: bundleIdentifier) else {
            return .none
        }
        let minimizedStates = windows(for: application.processIdentifier).compactMap(minimizedState(_:))
        return DockWindowCyclePlanner.action(
            forMinimizedStates: minimizedStates,
            targetWasFrontmost: targetWasFrontmost
        )
    }

    func cycleWindows(
        bundleIdentifier: String,
        action: DockWindowCycleAction
    ) -> DockWindowCycleAction {
        guard AXIsProcessTrusted(),
              action != .none,
              let application = runningApplication(for: bundleIdentifier) else {
            return .none
        }
        // Lock the action at Dock mouse-down. After native Dock activation has
        // settled, refresh only the AX elements and never re-plan from their
        // already-mutated minimized state.
        let windows = windows(for: application.processIdentifier).filter { minimizedState($0) != nil }

        let shouldMinimize = action == .minimizeAll
        if DockWindowCyclePlanner.shouldActivateApplication(for: action) {
            _ = application.activate(options: [.activateIgnoringOtherApps])
        }
        var changedWindow = false
        for (index, window) in windows.enumerated() {
            if shouldMinimize {
                let result = AXUIElementSetAttributeValue(
                    window,
                    kAXMinimizedAttribute as CFString,
                    kCFBooleanTrue
                )
                AppLogger.activation.debug("Dock AX minimize write index=\(index) result=\(result.rawValue)")
                changedWindow = result == .success || changedWindow
            } else {
                let restored = restoreAndRaise(window)
                AppLogger.activation.debug("Dock AX restore write index=\(index) success=\(restored)")
                changedWindow = restored || changedWindow
            }
        }
        let finalStates = windows.map(minimizedState(_:))
        let finalDescription = finalStates.map { state in
            state.map { $0 ? "minimized" : "visible" } ?? "unreadable"
        }.joined(separator: ",")
        AppLogger.activation.debug(
            "Dock AX final action=\(String(describing: action), privacy: .public) states=\(finalDescription, privacy: .public)"
        )
        return changedWindow && DockWindowCyclePlanner.didComplete(
            action: action,
            finalMinimizedStates: finalStates
        ) ? action : .none
    }

    private func runningApplication(for bundleIdentifier: String) -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == bundleIdentifier && !$0.isTerminated }
    }

    private func windows(for processIdentifier: pid_t) -> [AXUIElement] {
        let applicationElement = AXUIElementCreateApplication(processIdentifier)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(applicationElement, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else {
            return []
        }
        return windows
    }

    private func minimizedState(_ window: AXUIElement) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &value) == .success else {
            return nil
        }
        return (value as? NSNumber)?.boolValue
    }

    /// Prefer the window macOS already considers focused, then main, then the
    /// stable AX list order. This avoids making an arbitrary background window
    /// primary when an application exposes more than one minimized document.
    private func preferredWindow(
        from windows: [AXUIElement],
        processIdentifier: pid_t
    ) -> AXUIElement? {
        let applicationElement = AXUIElementCreateApplication(processIdentifier)
        let focusedWindow = elementAttribute(kAXFocusedWindowAttribute, from: applicationElement)
        let mainWindow = elementAttribute(kAXMainWindowAttribute, from: applicationElement)
        let focused = windows.map { window in
            focusedWindow.map { CFEqual(window, $0) } ?? false
        }
        let main = windows.map { window in
            mainWindow.map { CFEqual(window, $0) } ?? false
        }
        guard let index = AccessibilityWindowFocusPlanner.preferredIndex(focused: focused, main: main) else {
            return nil
        }
        return windows[index]
    }

    private func elementAttribute(_ attribute: String, from element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return unsafeBitCast(value, to: AXUIElement.self)
    }

    private func restoreAndRaise(_ window: AXUIElement) -> Bool {
        let unminimizeResult = AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        guard unminimizeResult == .success else { return false }
        let raiseResult = AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        let mainResult = AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
        let focusResult = AXUIElementSetAttributeValue(window, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        return minimizedState(window) == false
            && (raiseResult == .success || mainResult == .success || focusResult == .success)
    }
}
#endif

final class NativeFallbackWindowRestorer: AccessibilityWindowRestoring {
    func restoreWindows(
        bundleIdentifier: String,
        mode: AccessibilityWindowRestoreMode
    ) -> AccessibilityWindowRestoreResult {
        .unavailable
    }

    func plannedCycleAction(
        bundleIdentifier: String,
        targetWasFrontmost: Bool
    ) -> DockWindowCycleAction {
        .none
    }

    func cycleWindows(
        bundleIdentifier: String,
        action: DockWindowCycleAction
    ) -> DockWindowCycleAction {
        .none
    }
}

enum WindowRestorerFactory {
    static func makeDefault() -> AccessibilityWindowRestoring {
#if DIRECT
        AccessibilityWindowRestorer()
#else
        NativeFallbackWindowRestorer()
#endif
    }
}

/// Uses the Dock's Accessibility hierarchy to distinguish an actual Dock item
/// click from an ordinary mouse-driven activation. It deliberately does not
/// infer Dock intent from `NSEvent.pressedMouseButtons`.
#if DIRECT
final class DockAccessibilityHitTester {
    func bundleIdentifier(at point: CGPoint) -> String? {
        guard AXIsProcessTrusted(),
              let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else {
            return nil
        }

        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(AXUIElementCreateApplication(dock.processIdentifier), Float(point.x), Float(point.y), &hit) == .success,
              let hit else {
            return nil
        }

        var element: AXUIElement? = hit
        while let candidate = element {
            if DockAccessibilityHitTest.isDockItem(role: stringAttribute(kAXRoleAttribute, from: candidate)),
               let url = urlAttribute(kAXURLAttribute, from: candidate),
               let bundleIdentifier = DockAccessibilityHitTest.bundleIdentifier(from: url) {
                return bundleIdentifier
            }
            element = elementAttribute(kAXParentAttribute, from: candidate)
        }
        return nil
    }

    private func stringAttribute(_ attribute: String, from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private func urlAttribute(_ attribute: String, from element: AXUIElement) -> URL? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? URL
    }

    private func elementAttribute(_ attribute: String, from element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return unsafeBitCast(value, to: AXUIElement.self)
    }
}

final class DockClickMonitor {
    static let shared = DockClickMonitor()

    private var monitor: Any?
    private var activationObserver: NSObjectProtocol?
    private let hitTester = DockAccessibilityHitTester()
    private let intentCoordinator: DockClickIntentCoordinator

    init(intentCoordinator: DockClickIntentCoordinator = .shared) {
        self.intentCoordinator = intentCoordinator
    }

    func start(
        isEnabled: @escaping () -> Bool,
        onDockAppIntent: @escaping (String, pid_t, Date, Bool) -> DockClickActivationIntent?,
        onDockAppClick: @escaping (DockClickActivationIntent) -> Void
    ) {
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
            guard let self,
                  isEnabled(),
                  AXIsProcessTrusted(),
                  let point = DockAccessibilityHitTest.accessibilityPoint(
                      quartzLocation: event.cgEvent?.location,
                      appKitLocation: event.locationInWindow
                  ),
                  let bundleIdentifier = self.hitTester.bundleIdentifier(at: point),
                  let application = NSWorkspace.shared.runningApplications.first(where: {
                      $0.bundleIdentifier == bundleIdentifier && !$0.isTerminated
                  }) else {
                return
            }
            let now = Date()
            let targetWasFrontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier
                == application.processIdentifier
            guard let intent = onDockAppIntent(
                bundleIdentifier,
                application.processIdentifier,
                now,
                targetWasFrontmost
            ) else { return }
            if targetWasFrontmost {
                let delay = DockClickExecutionTiming.delay(
                    for: intent.action,
                    targetWasFrontmost: true
                )
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    guard let self,
                          AXIsProcessTrusted(),
                          self.intentCoordinator.isCurrent(intent, now: Date()) else {
                        return
                    }
                    onDockAppClick(intent)
                }
            }
        }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let intent = self.intentCoordinator.intent(
                    matchingBundleIdentifier: application.bundleIdentifier,
                    processIdentifier: application.processIdentifier,
                    now: Date()
                  ) else {
                return
            }
            guard AXIsProcessTrusted() else { return }
            let delay = DockClickExecutionTiming.delay(
                for: intent.action,
                targetWasFrontmost: intent.targetWasFrontmost
            )
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                onDockAppClick(intent)
            }
        }
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
            self.activationObserver = nil
        }
        intentCoordinator.clear()
    }
}
#endif
