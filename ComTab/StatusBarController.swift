//
//  StatusBarController.swift
//  Command Reopen
//
//  Created by CHEN on 2025/10/31.
//

import AppKit
import ApplicationServices
import Combine
import CoreGraphics
import os

@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    struct Presentation: Equatable {
        let showsUpgradeItem: Bool
        let canToggleAutoReopen: Bool
    }

    private struct VisibleWindowActionTarget {
        let application: NSRunningApplication
        let visibleWindowBounds: [CGRect]
    }

    private enum Constants {
        static let minimumVisibleWindowDimension: CGFloat = 32
        static let accessibilityMatchTolerance: CGFloat = 4
    }

    #if DIRECT
    private static let supportsAccessibilityWindowMinimization = true
    #else
    private static let supportsAccessibilityWindowMinimization = false
    #endif

    private let statusItem: NSStatusItem
    private let activationMonitor: ActivationMonitor
    private let accessController: AppAccessController
    private let launchManager = LaunchAtLoginManager()
    private var cancellables: Set<AnyCancellable> = []
    private var enableReopenItem: NSMenuItem?
    private var minimizeAllWindowsItem: NSMenuItem?
    private var hideAllWindowsItem: NSMenuItem?
    private var upgradeItem: NSMenuItem?

    init(activationMonitor: ActivationMonitor? = nil, accessController: AppAccessController? = nil) {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.activationMonitor = activationMonitor ?? .shared
        self.accessController = accessController ?? .shared
        super.init()
        configureButton()
        constructMenu()
        bindMenuState()
    }

    private func configureButton() {
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "command", accessibilityDescription: nil)
            button.imagePosition = .imageOnly
        }
    }

    private func constructMenu() {
        let menu = NSMenu()
        menu.delegate = self
        let presentation = Self.presentation(for: accessController)

        let enableReopenItem = NSMenuItem(
            title: String(localized: "Enable Command Reopen"),
            action: #selector(toggleEnableReopen),
            keyEquivalent: ""
        )
        enableReopenItem.target = self
        enableReopenItem.state = activationMonitor.isFeatureEnabled ? .on : .off
        menu.addItem(enableReopenItem)
        self.enableReopenItem = enableReopenItem

        // Launch at Login
        let launchItem = NSMenuItem(title: String(localized: "Launch at Login"), action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchItem.target = self
        launchItem.state = launchManager.isEnabled ? .on : .off
        if #available(macOS 13.0, *) {
            // enabled
        } else {
            launchItem.isEnabled = false
        }
        menu.addItem(launchItem)

        menu.addItem(.separator())

        if Self.supportsAccessibilityWindowMinimization {
            let minimizeAllWindowsItem = makeMenuItem(
                title: String(localized: "Minimize All Windows"),
                action: #selector(minimizeAllWindows)
            )
            menu.addItem(minimizeAllWindowsItem)
            self.minimizeAllWindowsItem = minimizeAllWindowsItem
        }

        let hideAllWindowsItem = makeMenuItem(
            title: String(localized: "Hide All Windows"),
            action: #selector(hideAllWindows)
        )
        menu.addItem(hideAllWindowsItem)
        self.hideAllWindowsItem = hideAllWindowsItem

        menu.addItem(.separator())

        // Upgrade to Pro (hidden when already pro)
        let upgradeItem = NSMenuItem(title: String(localized: "Upgrade to Pro..."), action: #selector(showProSettings), keyEquivalent: "")
        upgradeItem.target = self
        upgradeItem.isHidden = !presentation.showsUpgradeItem
        menu.addItem(upgradeItem)
        self.upgradeItem = upgradeItem

        menu.addItem(makeMenuItem(title: String(localized: "Settings..."), action: #selector(showSettings)))
        menu.addItem(.separator())

        switch accessController.distributionChannel {
        case .appStore:
            menu.addItem(makeMenuItem(title: String(localized: "Official"), action: #selector(openOfficialWebsite)))
            menu.addItem(makeMenuItem(title: String(localized: "Rate on App Store"), action: #selector(openAppStoreReview)))
        case .direct:
            menu.addItem(makeMenuItem(title: String(localized: "Get on Mac App Store"), action: #selector(openMacAppStore)))
            menu.addItem(makeMenuItem(title: String(localized: "GitHub"), action: #selector(openGitHub)))
        }

        // About
        let aboutItem = NSMenuItem(title: String(localized: "About"), action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        menu.addItem(.separator())

        // Quit
        let quitItem = NSMenuItem(title: String(localized: "Quit Command Reopen"), action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        updateManualWindowActionItems()
    }

    private func makeMenuItem(title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    private func bindMenuState() {
        activationMonitor.$isFeatureEnabled
            .receive(on: RunLoop.main)
            .sink { [weak self] isEnabled in
                self?.enableReopenItem?.state = isEnabled ? .on : .off
            }
            .store(in: &cancellables)

        accessController.$entitlementState
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else {
                    return
                }

                let presentation = Self.presentation(for: self.accessController)
                self.upgradeItem?.isHidden = !presentation.showsUpgradeItem

                // Disable feature when expired
                if !presentation.canToggleAutoReopen {
                    self.enableReopenItem?.isEnabled = false
                    self.enableReopenItem?.state = .off
                } else {
                    self.enableReopenItem?.isEnabled = true
                    // Restore actual toggle state when transitioning back to active
                    self.enableReopenItem?.state = self.activationMonitor.isFeatureEnabled ? .on : .off
                }
            }
            .store(in: &cancellables)
    }

    static func presentation(for accessController: AppAccessController) -> Presentation {
        Presentation(
            showsUpgradeItem: accessController.showsUpgradeEntry,
            canToggleAutoReopen: accessController.isCoreFeatureAvailable
        )
    }

    nonisolated static func canPerformManualWindowAction(
        frontmostBundleID: String?,
        isTerminated: Bool,
        selfBundleID: String? = Bundle.main.bundleIdentifier
    ) -> Bool {
        guard let frontmostBundleID, !frontmostBundleID.isEmpty else {
            return false
        }

        guard !isTerminated else {
            return false
        }

        return frontmostBundleID != selfBundleID
    }

    @objc private func toggleEnableReopen(_ sender: NSMenuItem) {
        guard accessController.isCoreFeatureAvailable else { return }
        activationMonitor.isFeatureEnabled.toggle()
        sender.state = activationMonitor.isFeatureEnabled ? .on : .off
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        let newValue = sender.state != .on
        launchManager.setEnabled(newValue)
        sender.state = launchManager.isEnabled ? .on : .off
    }

    @objc private func minimizeAllWindows() {
        let targetApplications = visibleWindowActionTargets()
        guard !targetApplications.isEmpty else {
            AppLogger.windowActions.info("Minimize All Windows ignored because there are no eligible visible apps.")
            updateManualWindowActionItems()
            return
        }

        guard requestAccessibilityAccessIfNeeded() else {
            AppLogger.windowActions.error("Minimize All Windows denied because Accessibility access is unavailable.")
            presentAccessibilityAccessAlert()
            return
        }

        AppLogger.windowActions.notice("Minimizing windows for \(targetApplications.count) visible apps on the current desktop.")

        for target in targetApplications {
            let minimizedCount = minimizeVisibleWindows(for: target)
            let bundleID = target.application.bundleIdentifier ?? "unknown app"
            AppLogger.windowActions.debug("Minimized \(minimizedCount) windows for \(bundleID).")
        }
    }

    @objc private func hideAllWindows() {
        let targetApplications = visibleWindowActionTargets()
        guard !targetApplications.isEmpty else {
            AppLogger.windowActions.info("Hide All Windows ignored because there are no eligible visible apps.")
            updateManualWindowActionItems()
            return
        }

        AppLogger.windowActions.notice("Hiding \(targetApplications.count) visible apps on the current desktop.")
        for target in targetApplications {
            let bundleID = target.application.bundleIdentifier ?? "unknown app"
            if target.application.hide() {
                AppLogger.windowActions.debug("Hide All Windows sent to \(bundleID).")
            } else {
                AppLogger.windowActions.error("Hide All Windows failed for \(bundleID).")
            }
        }
    }

    @objc private func showAbout() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        switch accessController.distributionChannel {
        case .appStore:
            NSApplication.shared.orderFrontStandardAboutPanel(options: [
                .credits: NSAttributedString(string: "Contact: \(ExternalLinks.contactEmailAddress)")
            ])
        case .direct:
            NSApplication.shared.orderFrontStandardAboutPanel(nil)
        }
    }

    @objc private func showSettings() {
        AppLogger.lifecycle.notice("Status bar requested settings window.")
        DispatchQueue.main.async { [activationMonitor, accessController] in
            SettingsWindowController.shared.show(
                activationMonitor: activationMonitor,
                accessController: accessController
            )
        }
    }

    @objc private func showProSettings() {
        guard accessController.showsProTab else {
            return
        }
        AppLogger.lifecycle.notice("Status bar requested Pro settings window.")
        DispatchQueue.main.async { [activationMonitor, accessController] in
            SettingsWindowController.shared.show(
                activationMonitor: activationMonitor,
                accessController: accessController,
                initialTab: .pro
            )
        }
    }

    @objc private func openOfficialWebsite() {
        openURL(ExternalLinks.officialURL)
    }

    @objc private func openAppStoreReview() {
        openURL(AppStoreLinks.reviewURL)
    }

    @objc private func openMacAppStore() {
        openURL(AppStoreLinks.productURL)
    }

    @objc private func openGitHub() {
        openURL(ExternalLinks.githubURL)
    }

    private func openURL(_ urlString: String) {
        guard let url = URL(string: urlString) else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    func menuWillOpen(_ menu: NSMenu) {
        updateManualWindowActionItems()
    }

    private func updateManualWindowActionItems() {
        let isEnabled = !visibleWindowActionTargets().isEmpty
        minimizeAllWindowsItem?.isEnabled = Self.supportsAccessibilityWindowMinimization && isEnabled
        hideAllWindowsItem?.isEnabled = isEnabled
    }

    private func visibleWindowActionTargets() -> [VisibleWindowActionTarget] {
        guard let windowInfoList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            AppLogger.windowActions.error("Unable to inspect on-screen windows for manual window actions.")
            return []
        }

        let runningApplicationsByPID = Dictionary(
            uniqueKeysWithValues: NSWorkspace.shared.runningApplications.map { ($0.processIdentifier, $0) }
        )
        var orderedPIDs: [pid_t] = []
        var visibleBoundsByPID: [pid_t: [CGRect]] = [:]

        for windowInfo in windowInfoList {
            guard Self.isEligibleVisibleWindow(
                windowInfo: windowInfo,
                minimumDimension: Constants.minimumVisibleWindowDimension
            ), let windowPID = ActivationMonitor.windowOwnerPID(from: windowInfo),
            let application = runningApplicationsByPID[windowPID],
            let bounds = Self.windowBounds(from: windowInfo),
            Self.canPerformManualWindowAction(
                frontmostBundleID: application.bundleIdentifier,
                isTerminated: application.isTerminated
            ) else {
                continue
            }

            if visibleBoundsByPID[windowPID] == nil {
                orderedPIDs.append(windowPID)
                visibleBoundsByPID[windowPID] = []
            }
            visibleBoundsByPID[windowPID, default: []].append(bounds)
        }

        return orderedPIDs.compactMap { pid in
            guard let application = runningApplicationsByPID[pid],
                  let visibleWindowBounds = visibleBoundsByPID[pid],
                  !visibleWindowBounds.isEmpty else {
                return nil
            }

            return VisibleWindowActionTarget(
                application: application,
                visibleWindowBounds: visibleWindowBounds
            )
        }
    }

    private func requestAccessibilityAccessIfNeeded() -> Bool {
        if AXIsProcessTrusted() {
            return true
        }

        AppLogger.windowActions.notice("Requesting Accessibility access for Minimize All Windows.")
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    private func minimizeVisibleWindows(for target: VisibleWindowActionTarget) -> Int {
        let applicationElement = AXUIElementCreateApplication(target.application.processIdentifier)
        var windowsValue: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            applicationElement,
            kAXWindowsAttribute as CFString,
            &windowsValue
        )

        guard result == .success, let windowElements = windowsValue as? [AXUIElement] else {
            AppLogger.windowActions.error(
                "Unable to enumerate accessibility windows for \(target.application.bundleIdentifier ?? "unknown app"). result=\(result.rawValue)"
            )
            return 0
        }

        var minimizedCount = 0
        for windowElement in windowElements {
            guard let frame = accessibilityWindowFrame(for: windowElement),
                  Self.matchesVisibleWindow(frame, visibleWindowBounds: target.visibleWindowBounds) else {
                continue
            }

            let setResult = AXUIElementSetAttributeValue(
                windowElement,
                kAXMinimizedAttribute as CFString,
                kCFBooleanTrue
            )

            if setResult == .success {
                minimizedCount += 1
            } else {
                AppLogger.windowActions.debug(
                    "Failed to minimize accessibility window for \(target.application.bundleIdentifier ?? "unknown app"). result=\(setResult.rawValue)"
                )
            }
        }

        return minimizedCount
    }

    private func presentAccessibilityAccessAlert() {
        NSApplication.shared.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Allow Accessibility Access to Minimize Windows")
        alert.informativeText = String(
            localized: "ComTab needs Accessibility permission to minimize other apps' windows. Enable Command Reopen in System Settings > Privacy & Security > Accessibility, then try again."
        )
        alert.addButton(withTitle: String(localized: "OK"))
        alert.runModal()
    }

    private static func isEligibleVisibleWindow(
        windowInfo: [String: Any],
        minimumDimension: CGFloat
    ) -> Bool {
        let ownerName = (windowInfo[kCGWindowOwnerName as String] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard ownerName?.isEmpty == false else {
            return false
        }

        let alpha = (windowInfo[kCGWindowAlpha as String] as? NSNumber)?.doubleValue
            ?? (windowInfo[kCGWindowAlpha as String] as? Double)
            ?? 1
        guard alpha > 0 else {
            return false
        }

        let layer = (windowInfo[kCGWindowLayer as String] as? NSNumber)?.intValue
            ?? (windowInfo[kCGWindowLayer as String] as? Int)
            ?? 0
        guard layer == 0 else {
            return false
        }

        guard let boundsDictionary = windowInfo[kCGWindowBounds as String] as? NSDictionary else {
            return false
        }

        var bounds = CGRect.zero
        guard CGRectMakeWithDictionaryRepresentation(boundsDictionary, &bounds) else {
            return false
        }

        return bounds.width >= minimumDimension && bounds.height >= minimumDimension
    }

    private static func windowBounds(from windowInfo: [String: Any]) -> CGRect? {
        guard let boundsDictionary = windowInfo[kCGWindowBounds as String] as? NSDictionary else {
            return nil
        }

        var bounds = CGRect.zero
        guard CGRectMakeWithDictionaryRepresentation(boundsDictionary, &bounds) else {
            return nil
        }

        return bounds
    }

    private func accessibilityWindowFrame(for windowElement: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?

        let positionResult = AXUIElementCopyAttributeValue(
            windowElement,
            kAXPositionAttribute as CFString,
            &positionValue
        )
        let sizeResult = AXUIElementCopyAttributeValue(
            windowElement,
            kAXSizeAttribute as CFString,
            &sizeValue
        )

        guard positionResult == .success,
              sizeResult == .success,
              let positionAXValue = positionValue,
              let sizeAXValue = sizeValue,
              CFGetTypeID(positionAXValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeAXValue) == AXValueGetTypeID() else {
            return nil
        }

        var position = CGPoint.zero
        var size = CGSize.zero

        guard AXValueGetType(positionAXValue as! AXValue) == .cgPoint,
              AXValueGetValue(positionAXValue as! AXValue, .cgPoint, &position),
              AXValueGetType(sizeAXValue as! AXValue) == .cgSize,
              AXValueGetValue(sizeAXValue as! AXValue, .cgSize, &size) else {
            return nil
        }

        return CGRect(origin: position, size: size)
    }

    private static func matchesVisibleWindow(_ frame: CGRect, visibleWindowBounds: [CGRect]) -> Bool {
        visibleWindowBounds.contains { candidate in
            abs(candidate.origin.x - frame.origin.x) <= Constants.accessibilityMatchTolerance &&
            abs(candidate.origin.y - frame.origin.y) <= Constants.accessibilityMatchTolerance &&
            abs(candidate.size.width - frame.size.width) <= Constants.accessibilityMatchTolerance &&
            abs(candidate.size.height - frame.size.height) <= Constants.accessibilityMatchTolerance
        }
    }
}
