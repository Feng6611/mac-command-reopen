//
//  OnboardingView.swift
//  CmdReopen
//
//  Created by CHEN on 2026/3/28.
//

import AppKit
import Combine
import ConfettiSwiftUI
import KikiOnboarding
import SwiftUI
import os
#if APPSTORE
import KikiCommerceCore
#endif

// MARK: - Flow

@MainActor
enum CommandReopenOnboardingFlow {
    static let windowSize = CGSize(width: 680, height: 600)
    static let stepCount = 4

    enum StepID {
        static let welcome = "welcome"
        static let tryMinimize = "tryMinimize"
        static let success = "success"
        static let finish = "finish"
    }

    static var tryMinimizeStepID: String { "custom.\(StepID.tryMinimize)" }

    static func makeCoordinator(
        tryMinimizeModel: OnboardingTryMinimizeModel,
        onMinimize: @escaping () -> Void,
        onFinished: @escaping @MainActor () -> Void
    ) -> KikiOnboardingCoordinator {
        let steps: [KikiOnboardingStep] = [
            .custom(id: StepID.welcome) { navigation in
                AnyView(WelcomeStepView(navigation: navigation))
            },
            .custom(id: StepID.tryMinimize) { _ in
                AnyView(TryMinimizeStepView(model: tryMinimizeModel, onMinimize: onMinimize))
            },
            .custom(id: StepID.success) { navigation in
                AnyView(SuccessStepView(navigation: navigation))
            },
            .custom(id: StepID.finish) { navigation in
                AnyView(FinishStepView(navigation: navigation))
            }
        ]

        return KikiOnboardingCoordinator(
            configuration: KikiOnboardingConfiguration(
                appName: "Command Reopen",
                steps: steps,
                // Same storage isFirstLaunch uses.
                completionKey: AppDefaults.RawKey.hasSeenOnboarding,
                canSkip: false,
                tint: DS.Colors.brandPrimary,
                windowAutosaveName: "CmdReopen.OnboardingWindow",
                windowTitle: AppLanguage.shared.string("Welcome"),
                windowSize: windowSize,
                minimumWindowSize: windowSize,
                closeDisposition: .keepPending
            ),
            onFinished: onFinished
        )
    }
}

// MARK: - Step Views

private struct WelcomeStepView: View {
    @ObservedObject private var appLanguage = AppLanguage.shared
    let navigation: KikiOnboardingNavigation

    var body: some View {
        KikiOnboardingScaffold(
            appName: "Command Reopen",
            title: AppLanguage.shared.string("Fix Cmd+Tab for minimized and closed windows"),
            bodyText: AppLanguage.shared.string("You minimize a window, Cmd+Tab back — but the window is gone. Command Reopen fixes that."),
            appIcon: NSApp.applicationIconImage,
            primaryAction: KikiOnboardingAction(title: AppLanguage.shared.string("Continue"), action: navigation.advance),
            tint: DS.Colors.brandPrimary,
            size: CommandReopenOnboardingFlow.windowSize,
            stepIndex: 0,
            stepCount: CommandReopenOnboardingFlow.stepCount,
            background: .plain,
            contentAlignment: .centered
        ) {
            OnboardingFlowDiagram()
                .padding(.horizontal, DS.Spacing.xxxl)
                .padding(.top, DS.Spacing.lg)
        }
    }
}

private struct TryMinimizeStepView: View {
    @ObservedObject private var appLanguage = AppLanguage.shared
    @ObservedObject var model: OnboardingTryMinimizeModel
    let onMinimize: () -> Void

    var body: some View {
        KikiOnboardingScaffold(
            appName: "Command Reopen",
            title: AppLanguage.shared.string("See it work"),
            appIcon: NSApp.applicationIconImage,
            primaryAction: KikiOnboardingAction(title: AppLanguage.shared.string("Minimize This Window")) {
                model.clearRetryHint()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                    onMinimize()
                }
            },
            tint: DS.Colors.brandPrimary,
            size: CommandReopenOnboardingFlow.windowSize,
            stepIndex: 1,
            stepCount: CommandReopenOnboardingFlow.stepCount,
            background: .plain,
            contentAlignment: .centered
        ) {
            VStack(spacing: DS.Spacing.xl) {
                HStack(spacing: DS.Spacing.sm) {
                    keyCap(glyph: "⌘", label: "command")
                    keyCap(glyph: "⇥", label: "tab")
                }
                .padding(.top, DS.Spacing.lg)

                Text(appLanguage.string("Click below, then press Cmd+Tab once — the window comes right back."))
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
        }
        .overlay(alignment: .top) {
            if model.showsRetryHint {
                retryHint
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.18), value: model.showsRetryHint)
    }

    /// Key caps drawn like real Apple keyboard keys: opaque key face with a
    /// hard bottom "lip" shadow for depth, the glyph centered above a small
    /// lowercase legend — matching the legend layout of Apple keyboards.
    /// Glyphs and legends stay verbatim across locales, like the keys do.
    private func keyCap(glyph: String, label: String) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            Text(verbatim: glyph)
                .font(.title)
            Spacer(minLength: 0)
            Text(verbatim: label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.top, DS.Spacing.md)
        .padding(.bottom, DS.Spacing.sm)
        .frame(width: 88, height: 84)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: .black.opacity(0.22), radius: 0.5, y: 1.5)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .strokeBorder(DS.Colors.cardBorder, lineWidth: 1)
        )
    }

    private var retryHint: some View {
        HStack(spacing: DS.Spacing.sm) {
            Image(systemName: "arrow.uturn.backward")
            Text(appLanguage.string("Didn’t come back? No worries — try again."))
        }
        .font(.callout.weight(.medium))
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.vertical, DS.Spacing.sm)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(DS.Colors.cardBorder, lineWidth: 0.5))
        .padding(.top, DS.Spacing.xl)
    }
}

private struct SuccessStepView: View {
    @ObservedObject private var appLanguage = AppLanguage.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let navigation: KikiOnboardingNavigation

    @State private var showsWedge = false
    @State private var confettiTrigger = 0

    var body: some View {
        KikiOnboardingScaffold(
            appName: "Command Reopen",
            title: AppLanguage.shared.string("It works!"),
            bodyText: AppLanguage.shared.string("Cmd+Tab now brings your windows back."),
            appIcon: NSApp.applicationIconImage,
            primaryAction: KikiOnboardingAction(title: AppLanguage.shared.string("Continue"), action: navigation.advance),
            tint: DS.Colors.brandPrimary,
            size: CommandReopenOnboardingFlow.windowSize,
            stepIndex: 2,
            stepCount: CommandReopenOnboardingFlow.stepCount,
            background: .plain,
            contentAlignment: .centered
        ) {
            // The single takeaway of this step: the product's wedge. A quiet
            // material panel (not a stark white card) keeps it native. The
            // confetti cannon fires from an invisible anchor — celebration
            // without a celebratory icon competing with the content.
            VStack(spacing: DS.Spacing.sm) {
                Color.clear
                    .frame(width: 1, height: 1)
                    .confettiCannon(
                        trigger: $confettiTrigger,
                        num: 30,
                        confettis: [.shape(.circle), .shape(.roundedCross)],
                        colors: [DS.Colors.brandPrimary, .orange, .purple, .pink],
                        confettiSize: 8,
                        rainHeight: 420,
                        radius: 260
                    )

                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 40, weight: .medium))
                    .foregroundStyle(DS.Colors.brandPrimary)
                    .padding(.bottom, DS.Spacing.xs)

                Text(appLanguage.string("Zero permissions"))
                    .font(.title2.bold())

                Text(appLanguage.string("No Accessibility. No Screen Recording. Nothing to grant."))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, DS.Spacing.xxl)
            .padding(.horizontal, DS.Spacing.xxl)
            .frame(maxWidth: .infinity)
            .background(
                .thinMaterial,
                in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                    .strokeBorder(DS.Colors.cardBorder, lineWidth: 1)
            )
            .padding(.top, DS.Spacing.lg)
            .scaleEffect(showsWedge ? 1 : 0.94)
            .opacity(showsWedge ? 1 : 0)
        }
        .onAppear {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            // Reduce Motion turns the celebration off, not the payoff: the
            // wedge appears at once with no spring, and the confetti — pure
            // decoration — is skipped entirely.
            guard !reduceMotion else {
                showsWedge = true
                return
            }
            withAnimation(.spring(response: 0.45, dampingFraction: 0.8).delay(0.15)) {
                showsWedge = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                confettiTrigger += 1
            }
        }
    }
}

/// The last step, and the only one that changes anything about the machine.
///
/// It answers "what happens now": the app keeps running across restarts, and
/// — for the free build — what it costs and how it gets funded. This is the
/// last moment the user is looking at a window; after Continue the app has no
/// Dock icon and lives in the menu bar.
private struct FinishStepView: View {
    @ObservedObject private var appLanguage = AppLanguage.shared
    @StateObject private var launchAtLoginManager = LaunchAtLoginManager()
    let navigation: KikiOnboardingNavigation

    var body: some View {
        KikiOnboardingScaffold(
            appName: "Command Reopen",
            title: AppLanguage.shared.string("You’re all set"),
            bodyText: bodyText,
            appIcon: NSApp.applicationIconImage,
            primaryAction: KikiOnboardingAction(
                title: AppLanguage.shared.string("Continue"),
                action: navigation.finish
            ),
            tint: DS.Colors.brandPrimary,
            size: CommandReopenOnboardingFlow.windowSize,
            stepIndex: 3,
            stepCount: CommandReopenOnboardingFlow.stepCount,
            background: .plain,
            contentAlignment: .centered
        ) {
            VStack(spacing: DS.Spacing.lg) {
                launchAtLoginCard
#if !APPSTORE
                communityBuildNote
#endif
            }
            .padding(.top, DS.Spacing.lg)
        }
        .onAppear {
            // Checked on arrival rather than after the fact: this app only
            // works while it is running, so a Mac that reboots without it
            // looks like an app that stopped working rather than one that was
            // never asked to start. The toggle is on screen and reversible in
            // the same breath, which is what separates a sensible default
            // from a decision made behind the user's back.
            //
            // When macOS holds the registration for approval, the prompt comes
            // up here rather than later: this step says the app will be there
            // after every restart, and a switch that quietly stayed off makes
            // that sentence untrue on the one screen the user is reading it.
            if !launchAtLoginManager.isEnabled {
                LaunchAtLoginApproval.present(for: launchAtLoginManager.setEnabled(true))
            }
        }
    }

    private var bodyText: String {
#if APPSTORE
        appLanguage.string(localized: "Your free trial is active — 14 days, and nothing is charged until you pick a plan.",
            comment: "Subtitle of the final onboarding step in the App Store build.")
#else
        appLanguage.string(localized: "Command Reopen is running, and it will be there after every restart.",
            comment: "Subtitle of the final onboarding step in the free build.")
#endif
    }

    private var launchAtLoginCard: some View {
        Toggle(isOn: launchAtLoginManager.binding) {
            VStack(alignment: .leading, spacing: 2) {
                Text(appLanguage.string("Launch at Login"))
                    .font(.callout.weight(.medium))
                Text(appLanguage.string(localized: "Command Reopen only restores windows while it is running.",
                    comment: "Explains why the final onboarding step turns on launch at login."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .toggleStyle(.switch)
        .tint(DS.Colors.brandPrimary)
        .padding(DS.Spacing.lg)
        .frame(maxWidth: .infinity)
        .background(
            .thinMaterial,
            in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .strokeBorder(DS.Colors.cardBorder, lineWidth: 1)
        )
    }

#if !APPSTORE
    /// What the user actually installed, said once, at the only moment they
    /// are certain to read it. Stated as a fact and a way to help rather than
    /// as a limitation: nothing here is locked, so an upsell would be a lie.
    private var communityBuildNote: some View {
        VStack(spacing: DS.Spacing.xs) {
            Text(appLanguage.string(localized: "This is the free community build",
                comment: "Heading of the free build's note on the final onboarding step."))
                .font(.callout.weight(.medium))

            Text(appLanguage.string(localized: "Every feature, no limits, for as long as you want it. The Mac App Store version is the same app — buying it is how the work gets paid for.",
                comment: "Body of the free build's note on the final onboarding step."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button(appLanguage.string("Get on Mac App Store")) {
                if let url = URL(string: AppStoreLinks.productURL) {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.plain)
            .font(.caption.weight(.medium))
            .foregroundStyle(DS.Colors.brandPrimary)
            .padding(.top, DS.Spacing.xxs)
        }
        .frame(maxWidth: .infinity)
    }
#endif
}

// MARK: - Product Content

private struct OnboardingFlowDiagram: View {
    @ObservedObject private var appLanguage = AppLanguage.shared
    @State private var showRestored = false

    var body: some View {
        HStack(spacing: 0) {
            flowStep(
                icon: "minus.circle",
                label: appLanguage.string("Minimized"),
                sublabel: appLanguage.string("window hidden"),
                tint: .orange
            )

            flowArrow

            flowStep(
                icon: "command",
                label: appLanguage.string("Cmd+Tab"),
                sublabel: appLanguage.string("switch back"),
                tint: DS.Colors.brandPrimary
            )

            flowArrow

            flowStep(
                icon: "macwindow",
                label: appLanguage.string("Restored"),
                sublabel: appLanguage.string("automatically"),
                tint: .green
            )
            .opacity(showRestored ? 1 : 0.4)
        }
        .frame(maxWidth: .infinity)
        .animation(.easeInOut(duration: 0.5), value: showRestored)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                showRestored = true
            }
        }
    }

    private func flowStep(icon: String, label: String, sublabel: String, tint: Color) -> some View {
        VStack(spacing: DS.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .background(
                    Circle().fill(tint.opacity(0.1))
                )

            VStack(spacing: 2) {
                Text(label)
                    .font(.callout.weight(.medium))
                Text(sublabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var flowArrow: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.quaternary)
            .frame(maxWidth: .infinity)
    }
}

// MARK: - Window Session

#if DEBUG
/// One-shot hand-off used only by the Debug Settings replay. It makes the
/// replay start under the same fresh-process condition as real onboarding.
enum OnboardingLaunchRequest {
    static func markPending(in defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: AppDefaults.RawKey.pendingOnboardingRelaunch)
        defaults.synchronize()
    }

    static func consume(in defaults: UserDefaults = .standard) -> Bool {
        guard defaults.bool(forKey: AppDefaults.RawKey.pendingOnboardingRelaunch) else {
            return false
        }

        defaults.removeObject(forKey: AppDefaults.RawKey.pendingOnboardingRelaunch)
        defaults.synchronize()
        return true
    }

    static func clear(in defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: AppDefaults.RawKey.pendingOnboardingRelaunch)
        defaults.synchronize()
    }
}
#endif

/// Tracks the product-owned half of the minimize tutorial. AppKit can restore a
/// miniaturized window before `NSApplication.didBecomeActiveNotification`, so
/// the activation handler must not infer this state from `NSWindow` alone.
struct OnboardingMinimizeReturnSession {
    private(set) var isAwaitingApplicationReturn = false

    mutating func recordWindowDidMiniaturize() {
        isAwaitingApplicationReturn = true
    }

    mutating func consumeApplicationReturn() -> Bool {
        guard isAwaitingApplicationReturn else {
            return false
        }
        isAwaitingApplicationReturn = false
        return true
    }

    /// The return timeout fired. Returns `true` when the user has not yet come
    /// back (so the caller should recover the window and offer a retry) and
    /// clears the awaiting flag — the recovery re-activates our own app, and a
    /// self-activation must not be mistaken for a completed tutorial.
    mutating func recordReturnTimeout() -> Bool {
        guard isAwaitingApplicationReturn else {
            return false
        }
        isAwaitingApplicationReturn = false
        return true
    }

    mutating func reset() {
        isAwaitingApplicationReturn = false
    }
}

/// View-facing state for the minimize tutorial. The window controller owns the
/// timeout logic and surfaces the retry hint here when the user does not return
/// with a single Cmd+Tab press.
@MainActor
final class OnboardingTryMinimizeModel: ObservableObject {
    @Published private(set) var showsRetryHint = false

    func showRetryHint() {
        showsRetryHint = true
    }

    func clearRetryHint() {
        showsRetryHint = false
    }
}

/// Owns the product side of onboarding: activation-policy switching for the
/// ⌘⇥ tutorial, the minimize-and-return session, and post-finish routing.
/// Window creation, step navigation, progress, and completion storage belong
/// to `KikiOnboardingCoordinator`.
@MainActor
final class OnboardingWindowController {
    static let shared = OnboardingWindowController()

    private var coordinator: KikiOnboardingCoordinator?
    private var appToReturnToAfterMinimize: NSRunningApplication?
    private var observers: [NSObjectProtocol] = []
    private var minimizeReturnSession = OnboardingMinimizeReturnSession()
    private let tryMinimizeModel = OnboardingTryMinimizeModel()
    private var activationConfirmationTask: Task<Void, Never>?
    private var returnTimeoutWorkItem: DispatchWorkItem?
    private let returnTimeout: TimeInterval = 10
    private var shouldRestoreActivationPolicyOnClose = false
#if DEBUG
    private var isRelaunchingForOnboarding = false
#endif

    var isVisible: Bool {
        coordinator?.isVisible == true
    }

    func showIfNeeded(accessController: AppAccessController) {
        guard accessController.shouldShowOnboarding else { return }
        present()
    }

#if DEBUG
    /// Replays onboarding from the Debug-only Settings row under the same
    /// fresh-process launch condition as the real first-launch flow.
    func replayFromDebugSettings() {
        relaunchForOnboarding()
    }

    func showAfterDebugRelaunch() {
        present()
    }
#endif

    private func present() {
        if let existingCoordinator = coordinator, existingCoordinator.isVisible {
            NSApplication.shared.activate(ignoringOtherApps: true)
            existingCoordinator.window?.makeKeyAndOrderFront(nil)
            return
        }
        coordinator = nil

        ActivationMonitor.shared.setOnboardingSessionActive(true)
        prepareRegularOnboardingSession()

        let coordinator = CommandReopenOnboardingFlow.makeCoordinator(
            tryMinimizeModel: tryMinimizeModel,
            onMinimize: { [weak self] in
                self?.miniaturizeTutorialWindow()
            },
            onFinished: { [weak self] in
                self?.handleFinished()
            }
        )
        self.coordinator = coordinator
        coordinator.start()
        installObservers()
    }

    func close() {
        coordinator?.close()
    }

    private var isWaitingForCommandTabReturn: Bool {
        coordinator?.currentStep?.id == CommandReopenOnboardingFlow.tryMinimizeStepID
    }

    /// Kiki's transparent onboarding window is intentionally borderless. This
    /// tutorial is the product-specific exception: it must be miniaturizable
    /// so users can exercise Command Reopen's Cmd+Tab behavior.
    ///
    /// The activation hand-off happens BEFORE the window miniaturizes: the
    /// Cmd+Tab switcher's first slot is the frontmost app, so Command Reopen
    /// must already be the *previous* app by the time the user can press
    /// Cmd+Tab. Handing off first closes the race where a fast user pressed
    /// Cmd+Tab while we were still frontmost.
    private func miniaturizeTutorialWindow() {
        guard coordinator?.window != nil else {
            return
        }

        tryMinimizeModel.clearRetryHint()
        guard let target = returnTargetOrFinder() else {
            tryMinimizeModel.showRetryHint()
            AppLogger.lifecycle.error("Onboarding activation hand-off has no eligible return target.")
            return
        }

        confirmActivation(of: target) { [weak self] didActivate in
            guard let self else { return }
            guard didActivate else {
                self.tryMinimizeModel.showRetryHint()
                AppLogger.lifecycle.error("Onboarding return-target activation was not confirmed.")
                return
            }
            guard self.isWaitingForCommandTabReturn,
                  let window = self.coordinator?.window else {
                return
            }

            window.styleMask = Self.styleMaskEnablingMiniaturization(window.styleMask)
            window.animationBehavior = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
                ? .none
                : .documentWindow
            // Keep the return target frontmost for Cmd+Tab ordering, but put
            // the inactive onboarding window onscreen so AppKit's native Dock
            // animation remains visible.
            window.orderFrontRegardless()
            window.displayIfNeeded()
            window.miniaturize(nil)
        }
    }

    static func styleMaskEnablingMiniaturization(
        _ styleMask: NSWindow.StyleMask
    ) -> NSWindow.StyleMask {
        styleMask.union(.miniaturizable)
    }

    private func prepareRegularOnboardingSession() {
        appToReturnToAfterMinimize = Self.bestReturnTargetBeforeActivatingSelf()
        NSApp.windows.forEach { $0.orderOut(nil) }
        shouldRestoreActivationPolicyOnClose = true
    }

#if DEBUG
    /// LaunchServices owns Cmd+Tab's process ordering. The Debug Settings replay
    /// launches a fresh foreground instance instead of promoting the existing
    /// accessory process, matching the real first-launch condition.
    private func relaunchForOnboarding() {
        guard !isRelaunchingForOnboarding else {
            return
        }

        isRelaunchingForOnboarding = true
        OnboardingLaunchRequest.markPending()

        let currentProcessIdentifier = ProcessInfo.processInfo.processIdentifier
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.createsNewApplicationInstance = true

        NSWorkspace.shared.openApplication(
            at: Bundle.main.bundleURL,
            configuration: configuration
        ) { [weak self] application, error in
            Task { @MainActor [weak self] in
                guard let self else { return }

                guard error == nil,
                      let application,
                      application.processIdentifier != currentProcessIdentifier else {
                    OnboardingLaunchRequest.clear()
                    self.isRelaunchingForOnboarding = false
                    AppLogger.lifecycle.error(
                        "Unable to launch a fresh foreground instance for onboarding: \(error?.localizedDescription ?? "no new process")."
                    )
                    return
                }

                AppLogger.lifecycle.notice(
                    "Fresh onboarding instance launched. Terminating previous menu-bar process."
                )
                NSApp.terminate(nil)
            }
        }
    }
#endif

    private func installObservers() {
        removeObservers()

        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleApplicationDidBecomeActive()
            }
        })

        if let window = coordinator?.window {
            observers.append(NotificationCenter.default.addObserver(
                forName: NSWindow.didMiniaturizeNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.handleWindowDidMiniaturize()
                }
            })

            observers.append(NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.handleWindowWillClose()
                }
            })
        }
    }

    private func removeObservers() {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
    }

    private func handleApplicationDidBecomeActive() {
        guard let coordinator,
              let window = coordinator.window,
              isWaitingForCommandTabReturn,
              minimizeReturnSession.consumeApplicationReturn() else {
            return
        }

        cancelReturnTimeout()
        tryMinimizeModel.clearRetryHint()
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
        coordinator.advance()
        AppLogger.lifecycle.notice("Onboarding minimize tutorial completed after app activation.")
    }

    private func handleWindowDidMiniaturize() {
        guard isWaitingForCommandTabReturn else {
            return
        }

        tryMinimizeModel.clearRetryHint()
        minimizeReturnSession.recordWindowDidMiniaturize()
        scheduleReturnTimeout()
        AppLogger.lifecycle.debug("Onboarding minimize tutorial is awaiting app activation.")
    }

    /// If the user does not return with a single Cmd+Tab press, recover the
    /// window so the tutorial is never a dead end: bring it back to the front,
    /// stay on the same step, and surface a gentle retry hint.
    private func handleReturnTimeout() {
        guard isWaitingForCommandTabReturn,
              minimizeReturnSession.recordReturnTimeout() else {
            return
        }
        returnTimeoutWorkItem = nil

        guard let window = coordinator?.window else {
            return
        }
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        tryMinimizeModel.showRetryHint()
        AppLogger.lifecycle.notice("Onboarding minimize tutorial timed out; recovered window for retry.")
    }

    private func scheduleReturnTimeout() {
        returnTimeoutWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                self?.handleReturnTimeout()
            }
        }
        returnTimeoutWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + returnTimeout, execute: workItem)
    }

    private func cancelReturnTimeout() {
        returnTimeoutWorkItem?.cancel()
        returnTimeoutWorkItem = nil
    }

    private func handleWindowWillClose() {
        removeObservers()
        cancelActivationConfirmation()
        cancelReturnTimeout()
        tryMinimizeModel.clearRetryHint()
        appToReturnToAfterMinimize = nil
        minimizeReturnSession.reset()
        ActivationMonitor.shared.setOnboardingSessionActive(false)
        restoreActivationPolicyIfNeeded()
    }

    private func handleFinished() {
        ActivationMonitor.shared.setOnboardingSessionActive(false)
        restoreActivationPolicyIfNeeded()
        coordinator = nil
        cancelActivationConfirmation()
        cancelReturnTimeout()
        tryMinimizeModel.clearRetryHint()
        minimizeReturnSession.reset()

        NSApp.windows.forEach { window in
            if window.title != "Settings" {
                window.orderOut(nil)
            }
        }

        // General, not About. Someone who has just been shown how the app
        // works lands on the pane that continues that — the settings it just
        // turned on, and the shortcuts sheet that places what they learned
        // inside the rest of the system. About is credits, status and price,
        // which is a strange thing to hand someone thirty seconds in.
        DispatchQueue.main.async {
            SettingsWindowController.shared.show(
                activationMonitor: .shared,
                reopenStatsStore: .shared,
                accessController: .shared,
                initialTab: .general
            )
        }
    }

    private func restoreActivationPolicyIfNeeded() {
        guard shouldRestoreActivationPolicyOnClose else {
            return
        }
        // The steady state of this menu bar app is always .accessory — on
        // first launch the app deliberately starts as .regular for the
        // Cmd+Tab tutorial, so "restore" must not return to that.
        NSApp.setActivationPolicy(.accessory)
        shouldRestoreActivationPolicyOnClose = false
    }

    /// Requests activation and waits for `NSWorkspace` to confirm the target is
    /// truly frontmost. Activation is cooperative on current macOS releases, so
    /// a request alone is not a safe ordering boundary for Cmd+Tab.
    private func confirmActivation(
        of target: NSRunningApplication,
        completion: @escaping @MainActor (Bool) -> Void
    ) {
        cancelActivationConfirmation()

        activationConfirmationTask = Task { @MainActor [weak self] in
            guard let self else { return }

            let maximumChecks = 30
            for check in 0..<maximumChecks {
                guard !Task.isCancelled else { return }

                if check.isMultiple(of: 5) {
                    Self.requestActivation(of: target)
                }

                if NSWorkspace.shared.frontmostApplication?.processIdentifier
                    == target.processIdentifier {
                    self.activationConfirmationTask = nil
                    completion(true)
                    return
                }

                try? await Task.sleep(nanoseconds: 100_000_000)
            }

            guard !Task.isCancelled else { return }
            self.activationConfirmationTask = nil
            completion(false)
        }
    }

    private func cancelActivationConfirmation() {
        activationConfirmationTask?.cancel()
        activationConfirmationTask = nil
    }

    private static func requestActivation(of target: NSRunningApplication) {
        let current = NSRunningApplication.current

        if #available(macOS 14.0, *) {
            NSApp.yieldActivation(to: target)
            if target.activate(from: current, options: []) {
                return
            }
        }

        _ = target.activate(options: [.activateIgnoringOtherApps])
    }

    private func returnTargetOrFinder() -> NSRunningApplication? {
        if let appToReturnToAfterMinimize,
           Self.isEligibleReturnTarget(appToReturnToAfterMinimize) {
            return appToReturnToAfterMinimize
        }

        return NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.apple.finder"
        ).first
    }

    private static func bestReturnTargetBeforeActivatingSelf() -> NSRunningApplication? {
        if let frontmost = NSWorkspace.shared.frontmostApplication,
           isEligibleReturnTarget(frontmost) {
            return frontmost
        }

        return NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.apple.finder"
        ).first
    }

    private static func isEligibleReturnTarget(_ app: NSRunningApplication) -> Bool {
        guard !app.isTerminated,
              let bundleID = app.bundleIdentifier,
              bundleID != Bundle.main.bundleIdentifier else {
            return false
        }

        return !ActivationMonitor.isIgnoredBundleID(bundleID)
    }
}
