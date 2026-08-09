import AppKit
import Combine
import KikiSettings
import os

@MainActor
final class SettingsNavigationModel: ObservableObject {
    static let shared = SettingsNavigationModel()
    @Published var isPaywallSheetPresented = false
    @Published var isTrialExitOfferPresented = false
#if DEBUG
    @Published var isTrialExitOfferDebugPreviewPresented = false
#endif
    @Published private(set) var paywallSource: PaywallSource = .settings

    func presentPaywall(source: PaywallSource = .settings) {
        paywallSource = source
        isPaywallSheetPresented = true
    }

    /// Presents the trial-exit offer after the paywall has finished closing.
    ///
    /// The paywall dismisses itself, so the offer cannot replace it in place;
    /// asking for a second sheet while the first is still on screen is what
    /// makes AppKit drop one of them. The hop to the next run loop lets the
    /// first sheet retract before the card is asked for.
    func presentTrialExitOffer() {
        DispatchQueue.main.async { [self] in
            isTrialExitOfferPresented = true
        }
    }

#if DEBUG
    func presentTrialExitOfferDebugPreview() {
        DispatchQueue.main.async { [self] in
            isTrialExitOfferDebugPreviewPresented = true
        }
    }
#endif
}

@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()

    let coordinator = KikiSettingsCoordinator(
        tabs: SettingsTab.kikiTabs(language: .shared),
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

    func refreshLocalizedTabs() {
        coordinator.updateTabs(SettingsTab.kikiTabs(language: .shared))
    }

    func prepareForSettingsScene(
        accessController: AppAccessController? = nil,
        initialTab: SettingsTab? = nil,
        presentsPaywall: Bool = false,
        paywallSource: PaywallSource = .settings
    ) {
        if let initialTab {
            AppLogger.lifecycle.notice("Preparing settings scene. initialTab=\(initialTab.rawValue)")
            coordinator.select(initialTab)
        }

        if presentsPaywall {
            coordinator.select(.about)
            SettingsNavigationModel.shared.presentPaywall(source: paywallSource)
        }

        coordinator.prepare()
    }

    func show(
        activationMonitor: ActivationMonitor? = nil,
        reopenStatsStore: ReopenStatsStore? = nil,
        accessController: AppAccessController? = nil,
        initialTab: SettingsTab? = nil,
        presentsPaywall: Bool = false,
        paywallSource: PaywallSource = .settings
    ) {
        prepareForSettingsScene(
            accessController: accessController,
            initialTab: initialTab,
            presentsPaywall: presentsPaywall,
            paywallSource: paywallSource
        )
        coordinator.open()
    }
}

@MainActor
final class SettingsOpener {
    static let shared = SettingsOpener()

    func prepare(
        initialTab: SettingsTab? = nil,
        presentsPaywall: Bool = false,
        paywallSource: PaywallSource = .settings
    ) {
        SettingsWindowController.shared.prepareForSettingsScene(
            initialTab: initialTab,
            presentsPaywall: presentsPaywall,
            paywallSource: paywallSource
        )
    }

    func open(
        initialTab: SettingsTab? = nil,
        presentsPaywall: Bool = false,
        paywallSource: PaywallSource = .settings
    ) {
        SettingsWindowController.shared.show(
            initialTab: initialTab,
            presentsPaywall: presentsPaywall,
            paywallSource: paywallSource
        )
    }
}
