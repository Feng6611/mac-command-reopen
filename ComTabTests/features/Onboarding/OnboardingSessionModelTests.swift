import Testing
@testable import Command_Reopen

struct OnboardingSessionModelTests {
    @MainActor
    @Test("Onboarding session advances through live test states")
    func onboardingSessionAdvancesThroughLiveTestStates() {
        let session = OnboardingSessionModel()

        #expect(session.phase == .welcome)
        #expect(!session.isWaitingForCommandTabReturn)

        session.moveToTryMinimize()
        #expect(session.phase == .tryMinimize)
        #expect(session.isWaitingForCommandTabReturn)

        session.markWindowReturned()
        #expect(session.phase == .success)
        #expect(!session.isWaitingForCommandTabReturn)

        session.moveToPaywall()
        #expect(session.phase == .paywall)
    }
}
