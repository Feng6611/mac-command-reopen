import Foundation

@MainActor
final class AppRouter {
    private let accessController: AppAccessController
    private let prepare: (SettingsTab?, Bool) -> Void
    private let open: (SettingsTab?, Bool) -> Void

    init(
        accessController: AppAccessController,
        prepareSettings: @escaping (SettingsTab?, Bool) -> Void,
        openSettings: @escaping (SettingsTab?, Bool) -> Void
    ) {
        self.accessController = accessController
        self.prepare = prepareSettings
        self.open = openSettings
    }

    func prepareSettings(initialTab: SettingsTab? = nil, presentsPaywall: Bool = false) {
        prepare(initialTab, presentsPaywall)
    }

    func openSettings(initialTab: SettingsTab? = nil, presentsPaywall: Bool = false) {
        open(initialTab, presentsPaywall)
    }

    /// Expiry is already visible in Settings and the menu's upgrade entry.
    /// A background recovery attempt must preserve the user's foreground app.
    func handleExpiredAccess() {
        accessController.markPromptHandled()
    }
}
