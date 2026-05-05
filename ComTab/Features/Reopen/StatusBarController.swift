//
//  StatusBarController.swift
//  Command Reopen
//
//  Created by CHEN on 2025/10/31.
//

import Foundation

enum StatusBarController {
    struct Presentation: Equatable {
        let showsUpgradeItem: Bool
        let canToggleAutoReopen: Bool
    }

    static func presentation(for accessController: AppAccessController) -> Presentation {
        Presentation(
            showsUpgradeItem: accessController.showsUpgradeEntry,
            canToggleAutoReopen: accessController.isCoreFeatureAvailable
        )
    }

    static func canPerformManualWindowAction(
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
}
