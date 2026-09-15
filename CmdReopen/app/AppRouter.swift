import Foundation

@MainActor
final class AppRouter {
    private let accessController: AppAccessController
    private let prepare: (SettingsTab?, Bool) -> Void
    private let open: (SettingsTab?, Bool) -> Void
    private let isSettingsVisible: () -> Bool

    init(
        accessController: AppAccessController,
        prepareSettings: @escaping (SettingsTab?, Bool) -> Void,
        openSettings: @escaping (SettingsTab?, Bool) -> Void,
        isSettingsVisible: @escaping () -> Bool
    ) {
        self.accessController = accessController
        self.prepare = prepareSettings
        self.open = openSettings
        self.isSettingsVisible = isSettingsVisible
    }

    func prepareSettings(initialTab: SettingsTab? = nil, presentsPaywall: Bool = false) {
        prepare(initialTab, presentsPaywall)
    }

    func openSettings(initialTab: SettingsTab? = nil, presentsPaywall: Bool = false) {
        open(initialTab, presentsPaywall)
    }

    /// Expiry asks the user to decide, so it opens the paywall rather than
    /// waiting to be found. Both triggers — a launch that resolves access, and
    /// the one-time nudge on Cmd+Tab — land here.
    ///
    /// The visibility guard is what keeps a second paywall from being asked
    /// for on top of the window already showing it.
    func handleExpiredAccess() {
        if !isSettingsVisible() {
            open(.about, true)
        }
        accessController.markPromptHandled()
    }
}
