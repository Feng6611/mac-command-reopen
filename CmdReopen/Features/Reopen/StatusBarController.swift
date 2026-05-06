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
}
