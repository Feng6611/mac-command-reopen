import Testing
@testable import Command_Reopen

struct SettingsAndStatusBarPresentationTests {
    @MainActor
    @Test("Settings tabs include About tab")
    func settingsTabsForDirect() {
        #expect(SettingsTab.visibleTabs(showProTab: true) == [.general, .statistics, .about])
        #expect(SettingsTab.about.title(for: .direct) == "About")
        #expect(SettingsTab.about.title(for: .appStore) == "About")
    }

    @MainActor
    @Test("Status bar presentation follows access controller state")
    func statusBarPresentation() {
        let directController = AppAccessController(distributionChannel: .direct)
        #expect(StatusBarController.presentation(for: directController) == .init(
            showsUpgradeItem: false,
            canToggleAutoReopen: true
        ))

        let source = MockCommerceStateSource(entitlementState: .expired)
        let masController = AppAccessController(
            distributionChannel: .appStore,
            commerceStateSource: source
        )
        #expect(StatusBarController.presentation(for: masController) == .init(
            showsUpgradeItem: true,
            canToggleAutoReopen: false
        ))
    }

}
