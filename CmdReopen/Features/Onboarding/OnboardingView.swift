//
//  OnboardingView.swift
//  CmdReopen
//
//  Created by CHEN on 2026/3/28.
//

#if APPSTORE
import AppKit
import Combine
import ConfettiSwiftUI
import KikiOnboarding
import SwiftUI
import os

// MARK: - Flow

@MainActor
enum CommandReopenOnboardingFlow {
    static let windowSize = CGSize(width: 680, height: 680)
    static let stepCount = 4

    enum StepID {
        static let welcome = "welcome"
        static let tryMinimize = "tryMinimize"
        static let success = "success"
        static let paywall = "paywall"
    }

    static var tryMinimizeStepID: String { "custom.\(StepID.tryMinimize)" }

    static func makeCoordinator(
        accessModel: CommandAccessModel,
        onMinimize: @escaping () -> Void,
        onFinished: @escaping @MainActor () -> Void
    ) -> KikiOnboardingCoordinator {
        let steps: [KikiOnboardingStep] = [
            .custom(id: StepID.welcome) { navigation in
                AnyView(WelcomeStepView(navigation: navigation))
            },
            .custom(id: StepID.tryMinimize) { _ in
                AnyView(TryMinimizeStepView(onMinimize: onMinimize))
            },
            .custom(id: StepID.success) { navigation in
                AnyView(SuccessStepView(navigation: navigation))
            },
            .custom(id: StepID.paywall) { navigation in
                AnyView(PaywallStepView(accessModel: accessModel, navigation: navigation))
            }
        ]

        return KikiOnboardingCoordinator(
            configuration: KikiOnboardingConfiguration(
                appName: "Command Reopen",
                steps: steps,
                // Same storage the paywall actions and isFirstLaunch already use.
                completionKey: AppDefaults.RawKey.hasSeenOnboarding,
                canSkip: false,
                tint: DS.Colors.brandPrimary,
                windowAutosaveName: "CmdReopen.OnboardingWindow",
                windowTitle: "Welcome",
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
    let navigation: KikiOnboardingNavigation

    var body: some View {
        KikiOnboardingScaffold(
            appName: "Command Reopen",
            title: "Fix ⌘⇥ for minimized and closed windows",
            bodyText: "You minimize a window, ⌘⇥ back — but the window is gone. Command Reopen fixes that.",
            appIcon: NSApp.applicationIconImage,
            primaryAction: KikiOnboardingAction(title: "Continue", action: navigation.advance),
            tint: DS.Colors.brandPrimary,
            size: CommandReopenOnboardingFlow.windowSize,
            stepIndex: 0,
            stepCount: CommandReopenOnboardingFlow.stepCount
        ) {
            OnboardingFlowDiagram()
                .padding(.horizontal, DS.Spacing.xxxl)
        }
    }
}

private struct TryMinimizeStepView: View {
    let onMinimize: () -> Void

    @State private var showMinimizeReturnHint = false

    var body: some View {
        KikiOnboardingScaffold(
            appName: "Command Reopen",
            title: "Try it yourself",
            bodyText: "See the magic in two steps.",
            iconSystemName: "hand.point.down.fill",
            primaryAction: KikiOnboardingAction(title: "Minimize Window") {
                showMinimizeReturnHint = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                    onMinimize()
                }
            },
            tint: DS.Colors.brandPrimary,
            size: CommandReopenOnboardingFlow.windowSize,
            stepIndex: 1,
            stepCount: CommandReopenOnboardingFlow.stepCount
        ) {
            VStack(spacing: DS.Spacing.lg) {
                OnboardingStepRow(
                    number: "1",
                    text: "Click \"Minimize Window\" below"
                )
                OnboardingStepRow(
                    number: "2",
                    text: "Press ⌘⇥ to switch back here"
                )
            }
        }
        .overlay(alignment: .top) {
            if showMinimizeReturnHint {
                minimizeReturnHint
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.18), value: showMinimizeReturnHint)
    }

    private var minimizeReturnHint: some View {
        HStack(spacing: DS.Spacing.sm) {
            Image(systemName: "command")
            Text("Now ⌘⇥ back to Command Reopen")
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
    let navigation: KikiOnboardingNavigation

    @State private var confettiTrigger = 0

    var body: some View {
        KikiOnboardingScaffold(
            appName: "Command Reopen",
            title: "It works!",
            bodyText: "Command Reopen runs in the background for every app — whenever you ⌘⇥ back, minimized windows reappear.",
            appIcon: NSApp.applicationIconImage,
            primaryAction: KikiOnboardingAction(title: "Continue", action: navigation.advance),
            tint: DS.Colors.brandPrimary,
            size: CommandReopenOnboardingFlow.windowSize,
            stepIndex: 2,
            stepCount: CommandReopenOnboardingFlow.stepCount
        ) {
            VStack(spacing: DS.Spacing.lg) {
                CelebrationMark()
                    .scaleEffect(0.68)
                    .confettiCannon(
                        trigger: $confettiTrigger,
                        num: 30,
                        confettis: [.shape(.circle), .shape(.roundedCross)],
                        colors: [DS.Colors.brandPrimary, .orange, .purple, .pink],
                        confettiSize: 8,
                        rainHeight: 500,
                        radius: 300
                    )

                HStack(spacing: DS.Spacing.sm) {
                    Image(systemName: "macwindow.on.rectangle")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(DS.Colors.brandPrimary)
                    Text("Works for Safari, Finder, Xcode, and every other app.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                confettiTrigger += 1
            }
        }
    }
}

private struct PaywallStepView: View {
    @ObservedObject var accessModel: CommandAccessModel
    let navigation: KikiOnboardingNavigation

    @State private var isPaywallSheetPresented = false
    @State private var didFinish = false

    var body: some View {
        KikiOnboardingScaffold(
            appName: "Command Reopen",
            title: "It works!",
            bodyText: "Command Reopen runs in the background for every app — whenever you ⌘⇥ back, minimized windows reappear.",
            appIcon: NSApp.applicationIconImage,
            primaryAction: KikiOnboardingAction(title: "Continue") {
                isPaywallSheetPresented = true
            },
            tint: DS.Colors.brandPrimary,
            size: CommandReopenOnboardingFlow.windowSize,
            stepIndex: 3,
            stepCount: CommandReopenOnboardingFlow.stepCount
        ) {
            EmptyView()
        }
        .onAppear {
            isPaywallSheetPresented = true
        }
        .sheet(isPresented: $isPaywallSheetPresented, onDismiss: handlePaywallDismiss) {
            PaywallSheetView(
                accessModel: accessModel,
                context: .onboarding,
                onFinish: {
                    didFinish = true
                    navigation.finish()
                }
            )
        }
    }

    private func handlePaywallDismiss() {
        guard !didFinish else {
            return
        }
        navigation.back()
    }
}

// MARK: - Product Content

private struct OnboardingStepRow: View {
    let number: String
    let text: String

    var body: some View {
        HStack(spacing: DS.Spacing.md) {
            Text(number)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(Circle().fill(DS.Colors.brandPrimary))

            Text(text)
                .font(.body)
        }
    }
}

private struct OnboardingFlowDiagram: View {
    @State private var showRestored = false

    var body: some View {
        HStack(spacing: 0) {
            flowStep(
                icon: "minus.circle",
                label: "Minimized",
                sublabel: "window hidden",
                tint: .orange
            )

            flowArrow

            flowStep(
                icon: "command",
                label: "⌘⇥",
                sublabel: "switch back",
                tint: DS.Colors.brandPrimary
            )

            flowArrow

            flowStep(
                icon: "macwindow",
                label: "Restored",
                sublabel: "automatically",
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

private struct CelebrationMark: View {
    @State private var animate = false

    var body: some View {
        ZStack {
            ForEach(0..<14, id: \.self) { index in
                Circle()
                    .fill(confettiColor(index))
                    .frame(width: index.isMultiple(of: 3) ? 8 : 6, height: index.isMultiple(of: 3) ? 8 : 6)
                    .offset(
                        x: animate ? cos(CGFloat(index) * .pi / 7) * 58 : 0,
                        y: animate ? sin(CGFloat(index) * .pi / 7) * 58 : 0
                    )
                    .opacity(animate ? 1 : 0)
            }

            Text("🎉")
                .font(.system(size: 64))
                .scaleEffect(animate ? 1 : 0.8)
        }
        .frame(width: 132, height: 132)
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.62)) {
                animate = true
            }
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
    }

    private func confettiColor(_ index: Int) -> Color {
        switch index % 4 {
        case 0: return DS.Colors.brandPrimary
        case 1: return DS.Colors.brandPrimary.opacity(0.5)
        case 2: return Color.orange.opacity(0.6)
        default: return Color.secondary.opacity(0.4)
        }
    }
}

// MARK: - Window Session

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
    private var previousActivationPolicy: NSApplication.ActivationPolicy = .accessory
    private var shouldRestoreActivationPolicyOnClose = false

    var isVisible: Bool {
        coordinator?.isVisible == true
    }

    func showIfNeeded(proStatusManager: CommandAccessModel) {
        guard proStatusManager.isFirstLaunch else { return }
        show(proStatusManager: proStatusManager)
    }

    func show(proStatusManager: CommandAccessModel) {
        if let coordinator, coordinator.isVisible {
            NSApplication.shared.activate(ignoringOtherApps: true)
            coordinator.window?.makeKeyAndOrderFront(nil)
            return
        }

        prepareRegularOnboardingSession()

        let coordinator = CommandReopenOnboardingFlow.makeCoordinator(
            accessModel: proStatusManager,
            onMinimize: { [weak self] in
                self?.coordinator?.window?.miniaturize(nil)
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

    private func prepareRegularOnboardingSession() {
        appToReturnToAfterMinimize = Self.bestReturnTargetBeforeActivatingSelf()
        NSApp.windows.forEach { $0.orderOut(nil) }
        previousActivationPolicy = NSApp.activationPolicy()
        shouldRestoreActivationPolicyOnClose = true
        NSApp.setActivationPolicy(.regular)
    }

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
              window.isMiniaturized else {
            return
        }

        window.deminiaturize(nil)
        window.makeKeyAndOrderFront(nil)
        coordinator.advance()
    }

    private func handleWindowDidMiniaturize() {
        guard isWaitingForCommandTabReturn else {
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            Task { @MainActor [weak self] in
                self?.activateReturnTargetOrFinder()
            }
        }
    }

    private func handleWindowWillClose() {
        removeObservers()
        appToReturnToAfterMinimize = nil
        restoreActivationPolicyIfNeeded()
    }

    private func handleFinished() {
        restoreActivationPolicyIfNeeded()
        coordinator = nil

        NSApp.windows.forEach { window in
            if window.title != "Settings" {
                window.orderOut(nil)
            }
        }

        DispatchQueue.main.async {
            SettingsWindowController.shared.show(
                activationMonitor: .shared,
                reopenStatsStore: .shared,
                accessController: .shared,
                initialTab: .about
            )
        }
    }

    private func restoreActivationPolicyIfNeeded() {
        guard shouldRestoreActivationPolicyOnClose else {
            return
        }
        NSApp.setActivationPolicy(previousActivationPolicy)
        shouldRestoreActivationPolicyOnClose = false
    }

    private func activateReturnTargetOrFinder() {
        if let appToReturnToAfterMinimize,
           Self.isEligibleReturnTarget(appToReturnToAfterMinimize) {
            appToReturnToAfterMinimize.activate(options: [.activateIgnoringOtherApps])
            return
        }

        if let finder = NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.apple.finder"
        ).first {
            finder.activate(options: [.activateIgnoringOtherApps])
        }
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
#endif
