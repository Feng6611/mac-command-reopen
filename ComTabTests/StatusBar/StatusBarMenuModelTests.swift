//
//  StatusBarMenuModelTests.swift
//  ComTabTests
//
//  Created by Codex on 2026/4/26.
//

import CoreGraphics
import Foundation
import Testing
@testable import Command_Reopen

@MainActor
private final class MockLaunchAtLoginManager: LaunchAtLoginManaging {
    var isEnabled: Bool

    init(isEnabled: Bool = false) {
        self.isEnabled = isEnabled
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
    }
}

private struct MockWindowInfoProvider: WindowInfoListing {
    var windows: [[String: Any]]?

    func onScreenWindowInfo() -> [[String: Any]]? {
        windows
    }
}

private struct MockWindowActionApplicationProvider: WindowActionApplicationProviding {
    var applications: [WindowActionApplication]

    var runningWindowActionApplications: [WindowActionApplication] {
        applications
    }
}

private final class MockURLOpener: URLOpening {
    private(set) var openedURLs: [URL] = []

    func open(_ url: URL) {
        openedURLs.append(url)
    }
}

private final class MockApplicationPresenter: ApplicationPresenting {
    private(set) var didTerminate = false
    private(set) var shownAboutChannels: [DistributionChannel] = []

    func activateIgnoringOtherApps() {}

    func showAbout(distributionChannel: DistributionChannel) {
        shownAboutChannels.append(distributionChannel)
    }

    func terminate() {
        didTerminate = true
    }
}

struct StatusBarMenuModelTests {
    @MainActor
    @Test("Launch at login writes through injected manager")
    func launchAtLoginUsesInjectedManager() {
        let launchManager = MockLaunchAtLoginManager()
        let model = StatusBarMenuModel(launchManager: launchManager)

        model.setLaunchAtLogin(true)

        #expect(model.launchAtLoginEnabled)
        #expect(launchManager.isEnabled)
    }

    @MainActor
    @Test("Hide all windows hides only apps with standard visible windows")
    func hideAllWindowsUsesWindowInspectorCandidates() {
        var hideCount = 0
        let targetPID: pid_t = 123
        let ignoredPID: pid_t = 456
        let target = WindowActionApplication(
            processIdentifier: targetPID,
            bundleIdentifier: "com.example.Visible",
            isTerminated: false,
            hide: {
                hideCount += 1
                return true
            }
        )
        let ignored = WindowActionApplication(
            processIdentifier: ignoredPID,
            bundleIdentifier: "com.example.LayerWindow",
            isTerminated: false,
            hide: {
                hideCount += 10
                return true
            }
        )
        let model = StatusBarMenuModel(
            windowInfoProvider: MockWindowInfoProvider(windows: [
                windowInfo(pid: targetPID),
                windowInfo(pid: ignoredPID, layer: 2)
            ]),
            applicationProvider: MockWindowActionApplicationProvider(applications: [target, ignored])
        )

        #expect(model.canHideAllWindows)
        model.hideAllWindows()

        #expect(hideCount == 1)
    }

    @MainActor
    @Test("URL and app presentation actions use injected services")
    func actionsUseInjectedServices() {
        let opener = MockURLOpener()
        let presenter = MockApplicationPresenter()
        let model = StatusBarMenuModel(urlOpener: opener, applicationPresenter: presenter)

        model.openURL("https://commandreopen.com")
        model.showAbout(distributionChannel: .appStore)
        model.quit()

        #expect(opener.openedURLs.map(\.absoluteString) == ["https://commandreopen.com"])
        #expect(presenter.shownAboutChannels == [.appStore])
        #expect(presenter.didTerminate)
    }

    private func windowInfo(
        pid: pid_t,
        layer: Int = 0,
        width: CGFloat = 640,
        height: CGFloat = 480
    ) -> [String: Any] {
        [
            kCGWindowOwnerPID as String: NSNumber(value: pid),
            kCGWindowIsOnscreen as String: true,
            kCGWindowAlpha as String: 1.0,
            kCGWindowLayer as String: layer,
            kCGWindowBounds as String: [
                "X": 0,
                "Y": 0,
                "Width": width,
                "Height": height
            ]
        ]
    }
}
