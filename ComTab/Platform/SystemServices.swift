//
//  SystemServices.swift
//  ComTab
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

    func showAbout(distributionChannel: DistributionChannel) {
        activateIgnoringOtherApps()
        switch distributionChannel {
        case .appStore:
            NSApplication.shared.orderFrontStandardAboutPanel(options: [
                .credits: NSAttributedString(string: "Contact: \(ExternalLinks.contactEmailAddress)")
            ])
        case .direct:
            NSApplication.shared.orderFrontStandardAboutPanel(nil)
        }
    }

    func terminate() {
        NSApplication.shared.terminate(nil)
    }
}

protocol LaunchAtLoginManaging: AnyObject {
    var isEnabled: Bool { get }

    func setEnabled(_ enabled: Bool)
}
