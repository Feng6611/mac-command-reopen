//
//  MenuBarIconSettings.swift
//  CmdReopen
//

import Combine
import Defaults
import Foundation
import SwiftUI

/// The user's choice about whether the menu bar icon is present.
///
/// App-owned, like the other persisted product choices: `StatusBarMenuController`
/// applies it, and `AppLifecycleCoordinator` reads it to decide what a launch
/// should show.
final class MenuBarIconSettings: ObservableObject {
    static let shared = MenuBarIconSettings()

    @Published var showsMenuBarIcon: Bool {
        didSet {
            guard showsMenuBarIcon != oldValue else { return }
            defaults[AppDefaults.showsMenuBarIcon] = showsMenuBarIcon
        }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        _showsMenuBarIcon = Published(initialValue: defaults[AppDefaults.showsMenuBarIcon])
    }

    var showsMenuBarIconBinding: Binding<Bool> {
        Binding(
            get: { self.showsMenuBarIcon },
            set: { self.showsMenuBarIcon = $0 }
        )
    }
}
