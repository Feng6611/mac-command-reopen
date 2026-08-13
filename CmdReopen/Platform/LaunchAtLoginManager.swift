//
//  LaunchAtLoginManager.swift
//  Command Reopen
//
//  Created by CHEN on 2025/10/31.
//

import AppKit
import Combine
import Foundation
import ServiceManagement
import SwiftUI
import os

/// What macOS did with the request, as far as the user needs to know.
///
/// The distinction that matters is `needsApproval`: `register()` can succeed
/// and still leave the item switched off, because macOS holds new login items
/// until the user allows them. Reading back `status == .enabled` — which is all
/// `isEnabled` can report — turns that into "the toggle snapped back on its
/// own", with no explanation attached.
enum LaunchAtLoginOutcome: Equatable {
    case succeeded
    /// Registered, but waiting for the user in System Settings › Login Items.
    /// macOS shows no prompt of its own for this, so the app has to.
    case needsApproval
    case failed(reason: String?)
}

final class LaunchAtLoginManager: ObservableObject, LaunchAtLoginManaging {
    @Published private(set) var isEnabled: Bool

    init() {
        isEnabled = Self.service.status == .enabled
    }

    private static var service: SMAppService { .mainApp }

    @discardableResult
    func setEnabled(_ enabled: Bool) -> LaunchAtLoginOutcome {
        let service = Self.service
        var failure: Error?

        do {
            if enabled {
                // Re-registering is what clears a stale record after the app
                // has moved or updated; `register()` on an already-enabled
                // service keeps the old one.
                if service.status == .enabled {
                    try? service.unregister()
                }
                try service.register()
            } else {
                try service.unregister()
            }
        } catch {
            failure = error
        }

        let status = service.status
        isEnabled = status == .enabled
        let outcome = Self.outcome(enabling: enabled, status: status, failure: failure)
        AppLogger.launchAtLogin.info(
            "Set launch at login to \(enabled, privacy: .public). status=\(status.rawValue, privacy: .public) outcome=\(String(describing: outcome), privacy: .public)"
        )
        return outcome
    }

    private static func outcome(
        enabling: Bool,
        status: SMAppService.Status,
        failure: Error?
    ) -> LaunchAtLoginOutcome {
        guard enabling else {
            // `unregister()` throws when there was nothing registered, which is
            // the state the caller asked for.
            return status == .enabled ? .failed(reason: failure?.localizedDescription) : .succeeded
        }

        switch status {
        case .enabled:
            return .succeeded
        case .requiresApproval:
            return .needsApproval
        default:
            return .failed(reason: failure?.localizedDescription)
        }
    }
}

extension LaunchAtLoginManager {
    /// Writes through and reports what happened, because every caller of this
    /// binding is a toggle the user just flipped: letting it snap back in
    /// silence is the one outcome that explains nothing.
    var binding: Binding<Bool> {
        Binding(
            get: { self.isEnabled },
            set: { LaunchAtLoginApproval.present(for: self.setEnabled($0)) }
        )
    }
}

/// The prompt macOS does not provide.
///
/// Login items have no system authorization dialog — `register()` either takes
/// effect or leaves the item waiting in System Settings › Login Items. So the
/// app asks, and takes the user to the one switch that finishes the job.
@MainActor
enum LaunchAtLoginApproval {
    static func present(for outcome: LaunchAtLoginOutcome) {
        let language = AppLanguage.shared
        let alert = NSAlert()
        alert.alertStyle = .informational

        switch outcome {
        case .succeeded:
            return
        case .needsApproval:
            alert.messageText = language.string(
                localized: "Allow Command Reopen to launch at login",
                comment: "Alert title shown when macOS holds the login item until the user approves it."
            )
            alert.informativeText = language.string(
                localized: "macOS holds new login items until you allow them. Open Login Items and switch Command Reopen on.",
                comment: "Alert body shown when macOS holds the login item until the user approves it."
            )
        case .failed(let reason):
            alert.messageText = language.string(
                localized: "Command Reopen could not be added to Login Items",
                comment: "Alert title shown when registering the login item failed outright."
            )
            alert.informativeText = reason ?? language.string(
                localized: "macOS turned the request down. You can add Command Reopen yourself in Login Items.",
                comment: "Alert body shown when registering the login item failed and macOS gave no reason."
            )
        }

        alert.addButton(withTitle: language.string(
            localized: "Open Login Items",
            comment: "Alert button that opens System Settings at the Login Items pane."
        ))
        alert.addButton(withTitle: language.string(
            localized: "Not Now",
            comment: "Alert button that dismisses the login item prompt without opening System Settings."
        ))

        // Attached to the window the user is looking at when there is one —
        // the Settings pane, or the last onboarding step — and free-standing
        // when the toggle was flipped from the menu bar.
        if let window = NSApp.keyWindow ?? NSApp.mainWindow, window.isVisible {
            alert.beginSheetModal(for: window) { response in
                MainActor.assumeIsolated { openLoginItemsIfAccepted(response) }
            }
        } else {
            NSApp.activate(ignoringOtherApps: true)
            openLoginItemsIfAccepted(alert.runModal())
        }
    }

    private static func openLoginItemsIfAccepted(_ response: NSApplication.ModalResponse) {
        guard response == .alertFirstButtonReturn else {
            return
        }
        SMAppService.openSystemSettingsLoginItems()
    }
}
