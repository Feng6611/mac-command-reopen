import AppKit
import Combine
import KikiSettings

enum SettingsSheet: String, Identifiable {
    case shortcuts, paywall, trialExit
#if DEBUG
    case trialExitDebug
#endif
    var id: String { rawValue }
}

@MainActor
final class SettingsNavigationModel: ObservableObject {
    static var shared: SettingsNavigationModel { AppComposition.shared.settingsNavigation }

    @Published var presentedSheet: SettingsSheet? {
        didSet {
            if oldValue != nil, presentedSheet == nil { isDismissing = true }
        }
    }
    private(set) var isDismissing = false
    private var pendingSheet: SettingsSheet?
    private var afterDismiss: (() -> Void)?

    var isPresenting: Bool { presentedSheet != nil || isDismissing }

    func presentPaywall() { present(.paywall) }
    func presentMacShortcuts() { present(.shortcuts) }
    func presentTrialExitOffer() { present(.trialExit) }
#if DEBUG
    func presentTrialExitOfferDebugPreview() { present(.trialExitDebug) }
#endif

    private func present(_ sheet: SettingsSheet) {
        guard presentedSheet != sheet else { return }
        if isPresenting {
            pendingSheet = sheet
            presentedSheet = nil
        } else {
            presentedSheet = sheet
        }
    }

    /// Run purchase follow-up only after the native sheet has closed.
    func performAfterDismiss(_ action: @escaping () -> Void) {
        afterDismiss = action
    }

    func sheetDidDismiss(canPresent: (SettingsSheet) -> Bool = { _ in true }) {
        isDismissing = false
        let next = pendingSheet
        pendingSheet = nil
        let action = afterDismiss
        afterDismiss = nil
        if let next, canPresent(next) {
            presentedSheet = next
        } else {
            action?()
        }
    }
}

@MainActor
final class SettingsWindowController {
    static var shared: SettingsWindowController { AppComposition.shared.settingsWindow }
    private let navigation: SettingsNavigationModel
    private let onPrepare: () -> Void
    let coordinator: KikiSettingsCoordinator<SettingsTab>

    init(navigation: SettingsNavigationModel, onPrepare: @escaping () -> Void) {
        self.navigation = navigation
        self.onPrepare = onPrepare
        coordinator = KikiSettingsCoordinator(
            tabs: SettingsTab.kikiTabs(language: .shared),
            initialTab: .general,
            windowController: KikiSettingsWindowController(
                frameAutosaveName: "CommandReopen.SettingsWindow",
                layout: KikiSettingsWindowLayout(
                    ideal: CGSize(width: DS.Window.settingsWidth, height: DS.Window.settingsHeight),
                    minimum: CGSize(width: DS.Window.settingsWidth, height: DS.Window.settingsMinimumHeight),
                    maximum: CGSize(width: DS.Window.settingsWidth, height: DS.Window.settingsHeight)
                )
            )
        )
    }

    var isVisible: Bool { coordinator.isVisible }

    func refreshLocalizedTabs() {
        coordinator.updateTabs(SettingsTab.kikiTabs(language: .shared))
    }

    func prepareForSettingsScene(initialTab: SettingsTab? = nil, presentsPaywall: Bool = false) {
        if let initialTab { coordinator.select(initialTab) }
        if presentsPaywall {
            coordinator.select(.about)
            navigation.presentPaywall()
        }
        coordinator.prepare()
        onPrepare()
    }

    func show(initialTab: SettingsTab? = nil, presentsPaywall: Bool = false) {
        prepareForSettingsScene(initialTab: initialTab, presentsPaywall: presentsPaywall)
        coordinator.open()
    }
}

/// Compatibility entry for AppKit menu actions; all routes reach the app router.
@MainActor
final class SettingsOpener {
    static let shared = SettingsOpener()

    func prepare(initialTab: SettingsTab? = nil, presentsPaywall: Bool = false) {
        AppComposition.shared.router.prepareSettings(initialTab: initialTab, presentsPaywall: presentsPaywall)
    }

    func open(initialTab: SettingsTab? = nil, presentsPaywall: Bool = false) {
        AppComposition.shared.router.openSettings(initialTab: initialTab, presentsPaywall: presentsPaywall)
    }
}
