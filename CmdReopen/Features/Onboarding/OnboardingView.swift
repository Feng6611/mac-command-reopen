//
//  OnboardingView.swift
//  CmdReopen
//
//  Created by CHEN on 2026/3/28.
//

import AppKit
import Combine
import ConfettiSwiftUI
import SwiftUI
import os

enum OnboardingPhase: Equatable {
    case welcome
    case tryMinimize
    case success
    case paywall

    var progressIndex: Int {
        switch self {
        case .welcome: return 0
        case .tryMinimize: return 1
        case .success: return 2
        case .paywall: return 3
        }
    }
}

@MainActor
final class OnboardingSessionModel: ObservableObject {
    @Published var phase: OnboardingPhase = .welcome

    var isWaitingForCommandTabReturn: Bool {
        phase == .tryMinimize
    }

    func moveToTryMinimize() {
        phase = .tryMinimize
    }

    func markWindowReturned() {
        phase = .success
    }

    func moveToPaywall() {
        phase = .paywall
    }
}

struct OnboardingView: View {
    @ObservedObject var session: OnboardingSessionModel
    @ObservedObject var proStatusManager: ProStatusManager

    var onMinimize: () -> Void
    var onFinish: () -> Void

    @State private var showMinimizeReturnHint = false
    @State private var isPaywallSheetPresented = false
    @State private var confettiTrigger = 0

    var body: some View {
        ZStack {
            switch session.phase {
            case .welcome:
                welcomePage
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            case .tryMinimize:
                tryMinimizePage
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            case .success:
                successPage
                    .transition(.scale(scale: 0.96).combined(with: .opacity))
            case .paywall:
                successPage
                    .transition(.scale(scale: 0.96).combined(with: .opacity))
            }

            if showMinimizeReturnHint {
                minimizeReturnHint
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(1)
            }
        }
        .animation(.easeInOut(duration: 0.22), value: session.phase)
        .animation(.easeInOut(duration: 0.18), value: showMinimizeReturnHint)
        .frame(width: 680, height: 680)
        .background {
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                RadialGradient(
                    colors: [DS.Colors.brandPrimary.opacity(0.06), .clear],
                    center: .top,
                    startRadius: 0,
                    endRadius: 400
                )
            }
            .ignoresSafeArea()
            .overlay(.ultraThinMaterial.opacity(0.5))
        }
        .modifier(OnChangeCompat(value: session.phase) {
            if session.phase != .tryMinimize {
                showMinimizeReturnHint = false
            }

            if session.phase == .paywall {
                isPaywallSheetPresented = true
            }
        })
        .onAppear {
            if session.phase == .paywall {
                isPaywallSheetPresented = true
            }
        }
        .sheet(isPresented: $isPaywallSheetPresented, onDismiss: handlePaywallDismiss) {
            PaywallSheetView(
                proStatusManager: proStatusManager,
                context: .onboarding,
                onFinish: onFinish
            )
        }
    }

    private var welcomePage: some View {
        onboardingPage(
            title: "Fix ⌘⇥ for minimized and closed windows",
            subtitle: "You minimize a window, ⌘⇥ back — but the window is gone. Command Reopen fixes that."
        ) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 88, height: 88)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .shadow(color: .black.opacity(0.08), radius: 10, y: 5)
        } content: {
            OnboardingFlowDiagram()
                .padding(.horizontal, OnboardingLayout.diagramHorizontalPadding)
        } footer: {
            onboardingPrimaryButton("Continue", width: OnboardingLayout.primaryButtonWidth) {
                session.moveToTryMinimize()
            }
        }
    }

    private var tryMinimizePage: some View {
        onboardingPage(
            title: "Try it yourself",
            subtitle: "See the magic in two steps."
        ) {
            Text("👇")
                .font(.system(size: 56))
        } content: {
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
            .padding(.horizontal, OnboardingLayout.contentHorizontalPadding)
        } footer: {
            Button {
                showMinimizeReturnHint = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                    onMinimize()
                }
            } label: {
                Label("Minimize Window", systemImage: "minus")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: OnboardingLayout.primaryButtonWidth)
                    .frame(height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                            .fill(DS.Colors.brandPrimary)
                    )
            }
            .buttonStyle(.plain)
        }
    }

    private var successPage: some View {
        onboardingPage(
            title: "It works!",
            subtitle: "Command Reopen runs in the background for every app — whenever you ⌘⇥ back, minimized windows reappear."
        ) {
            ZStack {
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
            }
        } content: {
            HStack(spacing: DS.Spacing.sm) {
                Image(systemName: "macwindow.on.rectangle")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(DS.Colors.brandPrimary)
                Text("Works for Safari, Finder, Xcode, and every other app.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, OnboardingLayout.contentHorizontalPadding)
        } footer: {
            onboardingPrimaryButton("Continue", width: OnboardingLayout.primaryButtonWidth) {
                session.moveToPaywall()
            }
            .confettiCannon(
                trigger: $confettiTrigger,
                num: 20,
                confettis: [.shape(.circle)],
                colors: [DS.Colors.brandPrimary, .orange, .purple],
                confettiSize: 6,
                rainHeight: 400,
                openingAngle: .degrees(40),
                closingAngle: .degrees(140),
                radius: 200
            )
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                confettiTrigger += 1
            }
        }
    }

    private var appIconMark: some View {
        Image(nsImage: NSApp.applicationIconImage)
            .resizable()
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            .shadow(color: .black.opacity(0.10), radius: 8, y: 4)
    }

    private var minimizeReturnHint: some View {
        VStack {
            HStack(spacing: DS.Spacing.sm) {
                Image(systemName: "command")
                Text("Now ⌘⇥ back to Command Reopen")
            }
            .font(DS.Typography.bodyMedium)
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.vertical, DS.Spacing.sm)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(DS.Colors.cardBorder, lineWidth: 0.5))
            .padding(.top, OnboardingLayout.titlebarInset + DS.Spacing.lg)

            Spacer()
        }
    }

    private func onboardingPage<Hero: View, Content: View, Footer: View>(
        title: String,
        subtitle: String,
        @ViewBuilder hero: () -> Hero,
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer
    ) -> some View {
        VStack(spacing: 0) {
            Spacer().frame(height: OnboardingLayout.topPadding)

            hero()
                .frame(height: OnboardingLayout.heroHeight)

            Spacer().frame(height: DS.Spacing.xl)

            Text(title)
                .font(DS.Typography.onboardingTitle)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .padding(.horizontal, OnboardingLayout.contentHorizontalPadding)

            Spacer().frame(height: DS.Spacing.sm)

            Text(subtitle)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, OnboardingLayout.contentHorizontalPadding)

            Spacer().frame(height: DS.Spacing.xl)

            content()

            Spacer()

            OnboardingProgressDots(currentIndex: session.phase.progressIndex)

            Spacer().frame(height: DS.Spacing.lg)

            footer()

            Spacer().frame(height: OnboardingLayout.bottomPadding)
        }
    }

    private func onboardingPrimaryButton(
        _ title: String,
        width: CGFloat,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: width)
                .frame(height: 44)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                        .fill(DS.Colors.brandPrimary)
                )
        }
        .buttonStyle(.plain)
    }

    private func handlePaywallDismiss() {
        if session.phase == .paywall {
            session.markWindowReturned()
        }
    }
}

private enum OnboardingLayout {
    static let titlebarInset: CGFloat = 12
    static let topPadding: CGFloat = 48 + titlebarInset
    static let bottomPadding: CGFloat = 36
    static let heroHeight: CGFloat = 88
    static let contentHorizontalPadding: CGFloat = 100
    static let primaryButtonWidth: CGFloat = 200
    static let diagramHorizontalPadding: CGFloat = 60
}

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

private struct OnboardingProgressDots: View {
    let currentIndex: Int
    private let count = 4

    var body: some View {
        HStack(spacing: DS.Spacing.sm) {
            ForEach(0..<count, id: \.self) { index in
                Circle()
                    .fill(index == currentIndex ? DS.Colors.brandPrimary : Color.secondary.opacity(0.2))
                    .frame(width: 6, height: 6)
                    .animation(.easeInOut(duration: 0.18), value: currentIndex)
            }
        }
        .frame(height: 10)
        .accessibilityLabel("Onboarding step \(currentIndex + 1) of \(count)")
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

// MARK: - Window Controller

@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    private enum WindowMetrics {
        static let title = "Welcome"
        static let size = NSSize(width: 680, height: 680)
    }

    static let shared = OnboardingWindowController()

    private var window: NSWindow?
    private var session: OnboardingSessionModel?
    private var proStatusManager: ProStatusManager?
    private var appToReturnToAfterMinimize: NSRunningApplication?
    private var didBecomeActiveObserver: NSObjectProtocol?
    private var previousActivationPolicy: NSApplication.ActivationPolicy = .accessory
    private var shouldRestoreActivationPolicyOnClose = false
    private var isFinishing = false

    var isVisible: Bool {
        window?.isVisible == true
    }

    func showIfNeeded(proStatusManager: ProStatusManager) {
        guard proStatusManager.isFirstLaunch else { return }
        show(proStatusManager: proStatusManager)
    }

    func show(proStatusManager: ProStatusManager) {
        guard window == nil else {
            presentExistingWindow()
            return
        }

        prepareRegularOnboardingSession()

        let session = OnboardingSessionModel()
        let contentView = makeContentView(session: session, proStatusManager: proStatusManager)
        let window = makeWindow(contentView: contentView)

        self.session = session
        self.proStatusManager = proStatusManager
        self.window = window
        self.isFinishing = false
        installActivationObserver()
        present(window)
    }

    func close() {
        window?.close()
    }

    private func presentExistingWindow() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func prepareRegularOnboardingSession() {
        appToReturnToAfterMinimize = Self.bestReturnTargetBeforeActivatingSelf()
        hideExistingAppWindowsForOnboarding()
        previousActivationPolicy = NSApp.activationPolicy()
        shouldRestoreActivationPolicyOnClose = true
        NSApp.setActivationPolicy(.regular)
    }

    private func makeContentView(
        session: OnboardingSessionModel,
        proStatusManager: ProStatusManager
    ) -> OnboardingView {
        OnboardingView(
            session: session,
            proStatusManager: proStatusManager,
            onMinimize: { [weak self] in
                self?.window?.miniaturize(nil)
            },
            onFinish: { [weak self] in
                self?.finishAndClose()
            }
        )
    }

    private func makeWindow(contentView: OnboardingView) -> NSWindow {
        let hostingController = NSHostingController(rootView: contentView)
        let window = NSWindow(contentViewController: hostingController)
        configure(window)
        return window
    }

    private func configure(_ window: NSWindow) {
        window.title = WindowMetrics.title
        window.delegate = self
        window.styleMask = [.titled, .miniaturizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.backgroundColor = .windowBackgroundColor
        window.isReleasedWhenClosed = false
        window.setContentSize(WindowMetrics.size)
        window.center()

        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
    }

    private func present(_ window: NSWindow) {
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func hideExistingAppWindowsForOnboarding() {
        NSApp.windows.forEach { existingWindow in
            guard existingWindow != window else {
                return
            }

            existingWindow.orderOut(nil)
        }
    }

    private func installActivationObserver() {
        didBecomeActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleApplicationDidBecomeActive()
            }
        }
    }

    private func handleApplicationDidBecomeActive() {
        guard let window,
              let session,
              session.isWaitingForCommandTabReturn,
              window.isMiniaturized else {
            return
        }

        window.deminiaturize(nil)
        window.makeKeyAndOrderFront(nil)
        session.markWindowReturned()
    }

    private func shiftFocusAwayAfterOnboardingMinimize() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            Task { @MainActor [weak self] in
                self?.activateReturnTargetOrFinder()
            }
        }
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

    private func finishAndClose() {
        isFinishing = true
        close()

        DispatchQueue.main.async {
            SettingsWindowController.shared.show(
                activationMonitor: .shared,
                reopenStatsStore: .shared,
                accessController: .shared,
                initialTab: .about
            )
        }
    }

    func windowDidMiniaturize(_ notification: Notification) {
        guard let session,
              session.isWaitingForCommandTabReturn else {
            return
        }

        shiftFocusAwayAfterOnboardingMinimize()
    }

    func windowWillClose(_ notification: Notification) {
        if let didBecomeActiveObserver {
            NotificationCenter.default.removeObserver(didBecomeActiveObserver)
            self.didBecomeActiveObserver = nil
        }

        window = nil
        session = nil
        proStatusManager = nil
        appToReturnToAfterMinimize = nil

        if shouldRestoreActivationPolicyOnClose {
            NSApp.setActivationPolicy(previousActivationPolicy)
            shouldRestoreActivationPolicyOnClose = false
        }

        if isFinishing {
            NSApp.windows.forEach { window in
                if window.title != "Settings" {
                    window.orderOut(nil)
                }
            }
        }
        isFinishing = false
    }
}
