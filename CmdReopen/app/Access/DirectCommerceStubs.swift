#if !APPSTORE
/// Keeps shared settings/navigation APIs source-compatible for the direct
/// target without importing any commerce or purchase implementation.
enum PaywallSource: String {
    case settings
    case statusBar = "status_bar"
    case onboarding
    case trialExpiredLaunch = "trial_expired_launch"
    case expiredReopenNudge = "expired_reopen_nudge"
}
#endif
