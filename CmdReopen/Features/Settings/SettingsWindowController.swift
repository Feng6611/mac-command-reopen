import AppKit
import Combine
import KikiSettings
import os

@MainActor
final class SettingsNavigationModel: ObservableObject {
    static let shared = SettingsNavigationModel()
    @Published var isPaywallSheetPresented = false

    func presentPaywall() {
        isPaywallSheetPresented = true
    }
}

@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()

    let coordinator = KikiSettingsCoordinator(
        tabs: SettingsTab.kikiTabs,
        initialTab: SettingsTab.general,
        windowController: KikiSettingsWindowController(
            frameAutosaveName: "CommandReopen.SettingsWindow",
            minimumContentSize: CGSize(
                width: DS.Window.settingsWidth,
                height: DS.Window.settingsHeight
            )
        )
    )

    var isVisible: Bool { coordinator.isVisible }

    func prepareForSettingsScene(
        accessController: AppAccessController? = nil,
        initialTab: SettingsTab? = nil,
        presentsPaywall: Bool = false
    ) {
        if let initialTab {
            AppLogger.lifecycle.notice("Preparing settings scene. initialTab=\(initialTab.rawValue)")
            coordinator.select(initialTab)
        }

        if presentsPaywall {
            coordinator.select(.about)
            SettingsNavigationModel.shared.presentPaywall()
        }

        coordinator.prepare()
    }

    func show(
        activationMonitor: ActivationMonitor? = nil,
        reopenStatsStore: ReopenStatsStore? = nil,
        accessController: AppAccessController? = nil,
        initialTab: SettingsTab? = nil,
        presentsPaywall: Bool = false
    ) {
        prepareForSettingsScene(
            accessController: accessController,
            initialTab: initialTab,
            presentsPaywall: presentsPaywall
        )
        coordinator.open()
    }
}

@MainActor
final class SettingsOpener {
    static let shared = SettingsOpener()

    func prepare(initialTab: SettingsTab? = nil, presentsPaywall: Bool = false) {
        SettingsWindowController.shared.prepareForSettingsScene(
            initialTab: initialTab,
            presentsPaywall: presentsPaywall
        )
    }

    func open(initialTab: SettingsTab? = nil, presentsPaywall: Bool = false) {
        SettingsWindowController.shared.show(
            initialTab: initialTab,
            presentsPaywall: presentsPaywall
        )
    }
}
