import Testing
@testable import Command_Reopen

struct AppAccessControllerTests {
    @MainActor
    @Test("Direct access controller keeps core feature unlocked and shows support tab only")
    func directAccessControllerDefaults() {
        let controller = AppAccessController(distributionChannel: .direct)

        #expect(controller.isCoreFeatureAvailable)
        #expect(controller.showsProTab)
        #expect(!controller.showsUpgradeEntry)
        #expect(!controller.shouldShowOnboarding)
    }

    @MainActor
    @Test("MAS access controller reflects commerce state updates")
    func masAccessControllerUpdates() {
        let source = MockCommerceStateSource(
            entitlementState: .trial,
            isFirstLaunch: true
        )
        let controller = AppAccessController(
            distributionChannel: .appStore,
            commerceStateSource: source
        )

        #expect(controller.isCoreFeatureAvailable)
        #expect(controller.showsProTab)
        #expect(controller.showsUpgradeEntry)
        #expect(controller.shouldShowOnboarding)

        source.update(entitlementState: .expired)
        #expect(!controller.isCoreFeatureAvailable)
        #expect(controller.showsUpgradeEntry)

        source.update(entitlementState: .pro)
        #expect(controller.isCoreFeatureAvailable)
        #expect(!controller.showsUpgradeEntry)
        #expect(controller.shouldShowOnboarding)
    }

    @MainActor
    @Test("MAS onboarding depends on first-launch state only")
    func masOnboardingDependsOnFirstLaunch() {
        let source = MockCommerceStateSource(
            entitlementState: .pro,
            isFirstLaunch: true
        )
        let controller = AppAccessController(
            distributionChannel: .appStore,
            commerceStateSource: source
        )

        #expect(controller.shouldShowOnboarding)

        source.isFirstLaunch = false
        #expect(!controller.shouldShowOnboarding)
    }

    @MainActor
    @Test("MAS access controller forwards pro settings prompt state")
    func masAccessControllerPromptHandling() {
        let source = MockCommerceStateSource(
            entitlementState: .expired,
            shouldOpenProSettings: true
        )
        let controller = AppAccessController(
            distributionChannel: .appStore,
            commerceStateSource: source
        )

        #expect(controller.shouldOpenProSettings)

        controller.markPromptHandled()

        #expect(!controller.shouldOpenProSettings)
        #expect(!source.shouldOpenProSettings)
    }
}
