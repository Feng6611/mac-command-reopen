//
//  OnboardingView.swift
//  ComTab
//
//  Created by CHEN on 2026/3/28.
//

import AppKit
import Combine
import SwiftUI
import os

enum OnboardingPhase: Equatable {
    case welcome
    case tryMinimize
    case success
    case paywall
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

    @State private var isLoadingOfferings = false
    @State private var isStartingTrial = false
    @State private var isPurchasingLifetime = false
    @State private var isRestoring = false

    private var lifetimeProduct: ProPlanProduct {
        proStatusManager.planProduct(for: .lifetime)
    }

    private var isBusy: Bool {
        isLoadingOfferings || isStartingTrial || isPurchasingLifetime || isRestoring
            || proStatusManager.purchaseInProgressPlan != nil
            || proStatusManager.isRestoringPurchases
    }

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
                paywallPage
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
        }
        .animation(.easeInOut(duration: 0.22), value: session.phase)
        .frame(width: 680, height: 680)
        .background(.regularMaterial)
    }

    private var welcomePage: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 48)

            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 88, height: 88)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .shadow(color: .black.opacity(0.08), radius: 10, y: 5)

            Spacer().frame(height: DS.Spacing.xl)

            Text("Welcome to Command Reopen")
                .font(.system(size: 24, weight: .bold))

            Spacer().frame(height: DS.Spacing.sm)

            Text("Bring minimized windows back when you return to an app with Command-Tab.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .padding(.horizontal, 120)

            Spacer().frame(height: DS.Spacing.xxxl)

            OnboardingDemoDiagram(isRestored: false)
                .padding(.horizontal, 88)

            Spacer()

            Button {
                session.moveToTryMinimize()
            } label: {
                Text("Continue")
                    .frame(width: 200)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Spacer().frame(height: 34)
        }
    }

    private var tryMinimizePage: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 42)

            DSIconBadge(systemName: "command", size: 58, iconSize: 24)

            Spacer().frame(height: DS.Spacing.xl)

            Text("Try it once")
                .font(.system(size: 24, weight: .bold))

            Spacer().frame(height: DS.Spacing.sm)

            Text("Use the real macOS flow. We'll bring this window back when you return.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 120)

            Spacer().frame(height: DS.Spacing.xxxl)

            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                OnboardingStepRow(
                    step: "1",
                    title: "Minimize this window",
                    detail: "Click the yellow window button, or use the button below."
                )
                OnboardingStepRow(
                    step: "2",
                    title: "Command-Tab back to Command Reopen",
                    detail: "When this app becomes active again, the window will return."
                )
            }
            .padding(.horizontal, 120)

            Spacer().frame(height: DS.Spacing.xxl)

            OnboardingDemoDiagram(isRestored: false)
                .padding(.horizontal, 88)

            Spacer()

            Button {
                onMinimize()
            } label: {
                Label("Minimize Window", systemImage: "minus")
                    .frame(width: 200)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            Spacer().frame(height: 30)
        }
    }

    private var successPage: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 44)

            CelebrationMark()

            Spacer().frame(height: DS.Spacing.xl)

            Text("Command Reopen is working")
                .font(.system(size: 24, weight: .bold))

            Spacer().frame(height: DS.Spacing.sm)

            Text("That was the core trick: when an app is active but its window is gone, Command Reopen brings it back.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .padding(.horizontal, 120)

            Spacer().frame(height: DS.Spacing.xxxl)

            OnboardingDemoDiagram(isRestored: true)
                .padding(.horizontal, 88)

            Spacer()

            Button {
                session.moveToPaywall()
            } label: {
                Text("Continue")
                    .frame(width: 200)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Spacer().frame(height: 34)
        }
    }

    private var paywallPage: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: 30)

            Text("Keep Command Reopen")
                .font(.system(size: 24, weight: .bold))

            Spacer().frame(height: DS.Spacing.xs)

            Text("Buy once, or continue your 2-day trial and decide after using it in your own workflow.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .padding(.horizontal, 120)

            Spacer().frame(height: DS.Spacing.xl)

            lifetimeCard
                .padding(.horizontal, 86)

            if let paywallErrorMessage = proStatusManager.paywallErrorMessage {
                Text(paywallErrorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 94)
                    .padding(.top, DS.Spacing.sm)
            }

            if let successMessage = proStatusManager.paywallSuccessMessage {
                Text(successMessage)
                    .font(DS.Typography.captionMedium)
                    .foregroundColor(Color(nsColor: .systemGreen))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 94)
                    .padding(.top, DS.Spacing.sm)
            }

            Spacer()

            VStack(spacing: DS.Spacing.sm) {
                Button {
                    Task { await purchaseLifetime() }
                } label: {
                    HStack(spacing: DS.Spacing.sm) {
                        if isPurchasingLifetime {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.white)
                        } else {
                            Image(systemName: "sparkles")
                        }
                        Text(lifetimeCTA)
                            .font(.headline)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
                    .background(
                        RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                            .fill(Color.accentColor)
                    )
                }
                .buttonStyle(.plain)
                .disabled(isBusy || !lifetimeProduct.isAvailable)
                .opacity(isBusy || !lifetimeProduct.isAvailable ? 0.65 : 1)

                Button {
                    Task { await startTrial() }
                } label: {
                    HStack(spacing: DS.Spacing.sm) {
                        if isStartingTrial {
                            ProgressView().controlSize(.small)
                        }
                        Text("Continue 2-Day Trial")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(isBusy)

                Button("Skip for Now") {
                    proStatusManager.finishOnboardingWithoutTrial()
                    onFinish()
                }
                .buttonStyle(.link)
                .font(.caption)
                .disabled(isBusy)
            }
            .padding(.horizontal, 94)

            Spacer().frame(height: DS.Spacing.md)

            footerLinks
                .padding(.bottom, 24)
        }
        .task {
            guard !isLoadingOfferings else { return }
            isLoadingOfferings = true
            await proStatusManager.loadOfferings()
            isLoadingOfferings = false
        }
    }

    private var lifetimeCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: DS.Spacing.md) {
                DSIconBadge(
                    systemName: "infinity",
                    iconColor: .accentColor,
                    backgroundColor: DS.Colors.accentTint,
                    size: 42,
                    iconSize: 18
                )

                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    HStack(spacing: DS.Spacing.sm) {
                        Text(lifetimeProduct.title)
                            .font(DS.Typography.headlineMedium)
                        if let badge = lifetimeProduct.badge {
                            StatusPill(text: badge, tone: .accent)
                        }
                    }
                    Text(lifetimeProduct.subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: DS.Spacing.xxs) {
                    Text(lifetimeProduct.displayPrice)
                        .font(DS.Typography.headlineSmall)
                        .foregroundColor(.accentColor)
                    Text("once")
                        .font(DS.Typography.captionMedium)
                        .foregroundColor(.secondary)
                }
            }
            .padding(DS.Spacing.xl)

            Divider()

            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                PaywallBenefitRow(icon: "command", text: "Reopen minimized windows when you Command-Tab back")
                PaywallBenefitRow(icon: "hand.raised", text: "Exclude apps that should stay quiet")
                PaywallBenefitRow(icon: "chart.bar.xaxis", text: "See how often it helped")
            }
            .padding(.horizontal, DS.Spacing.xl)
            .padding(.vertical, DS.Spacing.lg)
        }
        .dsCard()
    }

    private var footerLinks: some View {
        HStack(spacing: DS.Spacing.md) {
            Button(isRestoring ? "Restoring..." : "Restore Purchase") {
                Task { await restorePurchases() }
            }
            .buttonStyle(.link)
            .font(.caption)
            .disabled(isBusy)

            DSDotSeparator()

            Button("Terms") { openExternalURL(ExternalLinks.termsURL) }
                .buttonStyle(.link)
                .font(.caption)

            DSDotSeparator()

            Button("Privacy") { openExternalURL(ExternalLinks.privacyURL) }
                .buttonStyle(.link)
                .font(.caption)
        }
    }

    private var lifetimeCTA: String {
        guard lifetimeProduct.isAvailable else { return "Lifetime Unavailable" }
        return "Unlock Forever - \(lifetimeProduct.displayPrice)"
    }

    private func purchaseLifetime() async {
        guard lifetimeProduct.isAvailable else { return }
        isPurchasingLifetime = true
        defer { isPurchasingLifetime = false }

        do {
            try await proStatusManager.purchase(.lifetime)
            if proStatusManager.status.isPro {
                onFinish()
            }
        } catch {
            if (error as? ProPurchaseError) != .purchaseCancelled {
                AppLogger.purchase.error("Onboarding lifetime purchase failed: \(error.localizedDescription)")
            }
        }
    }

    private func startTrial() async {
        isStartingTrial = true
        defer { isStartingTrial = false }

        await proStatusManager.startTrial()
        onFinish()
    }

    private func restorePurchases() async {
        isRestoring = true
        defer { isRestoring = false }

        do {
            try await proStatusManager.restorePurchases()
            if proStatusManager.status.isPro {
                proStatusManager.finishOnboardingWithoutTrial()
                onFinish()
            }
        } catch {
            if (error as? ProPurchaseError) != .purchaseCancelled {
                AppLogger.purchase.error("Onboarding restore failed: \(error.localizedDescription)")
            }
        }
    }

    private func openExternalURL(_ urlString: String) {
        guard let url = URL(string: urlString) else {
            return
        }

        NSWorkspace.shared.open(url)
    }
}

private struct OnboardingStepRow: View {
    let step: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: DS.Spacing.md) {
            Text(step)
                .font(DS.Typography.captionMedium)
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.accentColor))

            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                Text(title)
                    .font(DS.Typography.bodyMedium)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct OnboardingDemoDiagram: View {
    let isRestored: Bool

    var body: some View {
        HStack(spacing: DS.Spacing.lg) {
            MiniWindow(isMinimized: !isRestored)

            VStack(spacing: DS.Spacing.xs) {
                Text("⌘")
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                Text("Tab")
                    .font(DS.Typography.microSemibold)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 50, height: 50)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )

            MiniWindow(isMinimized: false)
                .opacity(isRestored ? 1 : 0.45)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct MiniWindow: View {
    let isMinimized: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                Circle().fill(Color.red.opacity(0.8)).frame(width: 7, height: 7)
                Circle().fill(Color.yellow.opacity(0.85)).frame(width: 7, height: 7)
                Circle().fill(Color.green.opacity(0.8)).frame(width: 7, height: 7)
                Spacer()
            }
            .padding(7)
            .background(Color(nsColor: .controlBackgroundColor))

            if isMinimized {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.secondary.opacity(0.3))
                    .frame(width: 54, height: 6)
                    .padding(.vertical, 22)
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    RoundedRectangle(cornerRadius: 2).fill(Color.accentColor.opacity(0.65)).frame(width: 58, height: 6)
                    RoundedRectangle(cornerRadius: 2).fill(Color.secondary.opacity(0.25)).frame(width: 72, height: 5)
                    RoundedRectangle(cornerRadius: 2).fill(Color.secondary.opacity(0.2)).frame(width: 46, height: 5)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 14)
            }
        }
        .frame(width: 132, height: 92)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .stroke(DS.Colors.cardBorder, lineWidth: 1)
        )
    }
}

private struct CelebrationMark: View {
    @State private var animate = false

    var body: some View {
        ZStack {
            ForEach(0..<10, id: \.self) { index in
                Circle()
                    .fill(confettiColor(index))
                    .frame(width: 6, height: 6)
                    .offset(
                        x: animate ? cos(CGFloat(index) * .pi / 5) * 46 : 0,
                        y: animate ? sin(CGFloat(index) * .pi / 5) * 46 : 0
                    )
                    .opacity(animate ? 1 : 0)
            }

            Text("🎉")
                .font(.system(size: 54))
                .scaleEffect(animate ? 1 : 0.8)
        }
        .frame(width: 112, height: 112)
        .onAppear {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.62)) {
                animate = true
            }
        }
    }

    private func confettiColor(_ index: Int) -> Color {
        switch index % 4 {
        case 0: return .accentColor
        case 1: return .orange
        case 2: return Color(nsColor: .systemGreen)
        default: return Color(nsColor: .systemPink)
        }
    }
}

private struct PaywallBenefitRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: DS.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 18)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Window Controller

@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
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
            NSApplication.shared.activate(ignoringOtherApps: true)
            window?.makeKeyAndOrderFront(nil)
            return
        }

        appToReturnToAfterMinimize = Self.bestReturnTargetBeforeActivatingSelf()
        hideExistingAppWindowsForOnboarding()
        previousActivationPolicy = NSApp.activationPolicy()
        shouldRestoreActivationPolicyOnClose = true
        NSApp.setActivationPolicy(.regular)

        let session = OnboardingSessionModel()
        let contentView = OnboardingView(
            session: session,
            proStatusManager: proStatusManager,
            onMinimize: { [weak self] in
                self?.window?.performMiniaturize(nil)
            },
            onFinish: { [weak self] in
                self?.finishAndClose()
            }
        )

        let hostingController = NSHostingController(rootView: contentView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "Welcome"
        window.delegate = self
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 680, height: 680))
        window.center()

        self.session = session
        self.proStatusManager = proStatusManager
        self.window = window
        self.isFinishing = false
        installActivationObserver()

        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.close()
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
