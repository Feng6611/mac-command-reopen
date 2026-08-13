//
//  SystemServices.swift
//  CmdReopen
//
//  Created by Codex on 2026/4/26.
//

import AppKit
import CoreGraphics
import Foundation

protocol WindowInfoListing {
    func onScreenWindowInfo() -> [[String: Any]]?
}

struct CoreGraphicsWindowInfoProvider: WindowInfoListing {
    func onScreenWindowInfo() -> [[String: Any]]? {
        CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]]
    }
}

protocol URLOpening {
    func open(_ url: URL)
}

struct WorkspaceURLOpener: URLOpening {
    func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }
}

protocol ApplicationPresenting {
    func activateIgnoringOtherApps()
    func showAbout(distributionChannel: DistributionChannel)
    func terminate()
}

struct SharedApplicationPresenter: ApplicationPresenting {
    func activateIgnoringOtherApps() {
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    /// The system's own About panel: name, icon, version, copyright, nothing
    /// else. Contact details live in Settings ▸ About, where they can be
    /// copied; repeating them here only made the panel taller.
    func showAbout(distributionChannel: DistributionChannel) {
        activateIgnoringOtherApps()
        NSApplication.shared.orderFrontStandardAboutPanel(nil)
    }

    func terminate() {
        NSApplication.shared.terminate(nil)
    }
}

protocol LaunchAtLoginManaging: AnyObject {
    var isEnabled: Bool { get }

    /// Returns what macOS actually did, which `isEnabled` alone cannot say:
    /// a registration awaiting the user's approval reads as "not enabled".
    @discardableResult
    func setEnabled(_ enabled: Bool) -> LaunchAtLoginOutcome
}
