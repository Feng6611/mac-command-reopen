//
//  OnboardingView.swift
//  ComTab
//
//  Created by CHEN on 2026/3/28.
//

import AppKit
import Combine
import RevenueCatCommerceKit
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
    @State private var isLoadingOfferings = false
    @State private var isStartingTrial = false
    @State private var isPurchasingLifetime = false
    @State private var isRestoring = false

    private var lifetimeProduct: ProPlanProduct {
        proStatusManager.planProduct(for: .lifetime)
    }

    private var yearlyProduct: ProPlanProduct {
        proStatusManager.planProduct(for: .yearly)
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

            if showMinimizeReturnHint {
                minimizeReturnHint
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(1)
            }
        }
        .animation(.easeInOut(duration: 0.22), value: session.phase)
        .animation(.easeInOut(duration: 0.18), value: showMinimizeReturnHint)
        .frame(width: 680, height: 680)
        .background(Color(nsColor: .windowBackgroundColor))
        .background {
            RadialGradient(
                colors: [DS.Colors.brandPrimary.opacity(0.06), .clear],
                center: .top,
                startRadius: 0,
                endRadius: 400
            )
        }
        .modifier(OnChangeCompat(value: session.phase) {
            if session.phase != .tryMinimize {
                showMinimizeReturnHint = false
            }
        })
    }

    private var welcomePage: some View {
        onboardingPage(
            title: "Never lose a minimized window again",
            subtitle: "You minimize a window, Command-Tab back — but the window is gone. Command Reopen fixes that."
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
            subtitle: "Two quick steps to see it in action."
        ) {
            DSIconBadge(
                systemName: "command",
                iconColor: DS.Colors.brandPrimary,
                backgroundColor: DS.Colors.brandPrimary.opacity(0.12),
                size: 64,
                iconSize: 26
            )
        } content: {
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                OnboardingStepRow(
                    step: "1",
                    title: "Minimize this window",
                    detail: "Use the button below to minimize."
                )
                OnboardingStepRow(
                    step: "2",
                    title: "Command-Tab back",
                    detail: "Switch to another app, then ⌘Tab back here — the window reappears automatically."
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
            subtitle: "Command Reopen runs in the background for every app — whenever you ⌘Tab back, minimized windows reappear."
        ) {
            CelebrationMark()
                .scaleEffect(0.68)
        } content: {
            HStack(spacing: DS.Spacing.sm) {
                Image(systemName: "macwindow.on.rectangle")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(DS.Colors.brandPrimary)
                Text("Works for Safari, Finder, Xcode, and every other app.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, OnboardingLayout.contentHorizontalPadding)
        } footer: {
            onboardingPrimaryButton("Continue", width: OnboardingLayout.primaryButtonWidth) {
                session.moveToPaywall()
            }
        }
    }

    @State private var selectedPlan: CommercePlan = .lifetime

    private var selectedProduct: ProPlanProduct {
        proStatusManager.planProduct(for: selectedPlan)
    }

    private var paywallPage: some View {
        VStack(spacing: 0) {
            Spacer().frame(height: OnboardingLayout.titlebarInset + 36)

            appIconMark

            Spacer().frame(height: DS.Spacing.lg)

            Text("Keep Command Reopen")
                .font(DS.Typography.onboardingTitle)
                .multilineTextAlignment(.center)

            Text("One-time purchase · no subscriptions")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.top, DS.Spacing.xs)

            Spacer().frame(height: DS.Spacing.lg)

            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                PaywallBenefitRow(icon: "checkmark.circle", text: "Never lose a minimized window again")
                PaywallBenefitRow(icon: "checkmark.circle", text: "Keep Command-Tab focused and predictable")
                PaywallBenefitRow(icon: "checkmark.circle", text: "Exclude apps that should stay quiet")
            }
            .frame(width: 330, alignment: .leading)

            Spacer().frame(height: DS.Spacing.xl)

            earlyBirdBadge

            Spacer().frame(height: DS.Spacing.md)

            HStack(spacing: DS.Spacing.sm) {
                OnboardingPlanCard(
                    product: yearlyProduct,
                    isSelected: selectedPlan == .yearly,
                    onSelect: { selectedPlan = .yearly }
                )
                OnboardingPlanCard(
                    product: lifetimeProduct,
                    isSelected: selectedPlan == .lifetime,
                    onSelect: { selectedPlan = .lifetime }
                )
            }
            .padding(.horizontal, OnboardingLayout.paywallHorizontalPadding)

            if let paywallErrorMessage = proStatusManager.paywallErrorMessage {
                Text(paywallErrorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, OnboardingLayout.paywallHorizontalPadding)
                    .padding(.top, DS.Spacing.sm)
            }

            if let successMessage = proStatusManager.paywallSuccessMessage {
                Text(successMessage)
                    .font(DS.Typography.captionMedium)
                    .foregroundColor(Color(nsColor: .systemGreen))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, OnboardingLayout.paywallHorizontalPadding)
                    .padding(.top, DS.Spacing.sm)
            }

            Spacer()

            VStack(spacing: DS.Spacing.sm) {
                Button {
                    Task { await startTrial() }
                } label: {
                    HStack(spacing: DS.Spacing.sm) {
                        if isStartingTrial {
                            ProgressView().controlSize(.small).tint(.white)
                        }
                        Text("Start 2-Day Free Trial")
                            .font(.headline)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                            .fill(DS.Colors.brandPrimary)
                    )
                }
                .buttonStyle(.plain)
                .disabled(isBusy)

                Button {
                    Task { await purchaseSelectedPlan() }
                } label: {
                    HStack(spacing: DS.Spacing.sm) {
                        if isPurchasingLifetime {
                            ProgressView().controlSize(.small)
                        }
                        Text(purchaseCTA)
                            .font(.headline)
                    }
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                            .strokeBorder(DS.Colors.cardBorder, lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)
                .disabled(isBusy || !selectedProduct.isAvailable)
                .opacity(isBusy || !selectedProduct.isAvailable ? 0.4 : 1)
            }
            .padding(.horizontal, OnboardingLayout.paywallHorizontalPadding)

            Spacer().frame(height: DS.Spacing.md)

            OnboardingProgressDots(currentIndex: session.phase.progressIndex)

            Spacer().frame(height: DS.Spacing.md)

            paywallFooter
                .padding(.bottom, OnboardingLayout.bottomPadding)
        }
        .animation(.easeInOut(duration: 0.15), value: selectedPlan)
        .task {
            guard !isLoadingOfferings else { return }
            isLoadingOfferings = true
            await proStatusManager.loadOfferings()
            isLoadingOfferings = false
        }
    }

    private var appIconMark: some View {
        Image(nsImage: NSApp.applicationIconImage)
            .resizable()
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            .shadow(color: .black.opacity(0.10), radius: 8, y: 4)
    }

    private var earlyBirdBadge: some View {
        HStack(spacing: DS.Spacing.xs) {
            Circle()
                .fill(DS.Colors.brandPrimary)
                .frame(width: 5, height: 5)
            Text("Early Bird · Limited Time")
                .font(DS.Typography.microSemibold)
        }
        .foregroundStyle(DS.Colors.brandPrimary)
        .padding(.horizontal, DS.Spacing.md)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(DS.Colors.brandPrimary.opacity(0.08))
        )
        .overlay(
            Capsule()
                .strokeBorder(DS.Colors.brandPrimary.opacity(0.2), lineWidth: 0.5)
        )
    }

    private var minimizeReturnHint: some View {
        VStack {
            HStack(spacing: DS.Spacing.sm) {
                Image(systemName: "command")
                Text("Now Command-Tab back to Command Reopen")
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
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, OnboardingLayout.contentHorizontalPadding)

            Spacer().frame(height: DS.Spacing.xxxl)

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

    private var paywallFooter: some View {
        HStack(spacing: DS.Spacing.md) {
            Button(isRestoring ? "Restoring..." : "Restore Purchase") {
                Task { await restorePurchases() }
            }
            .disabled(isBusy)

            DSDotSeparator()

            Button("Skip for Now") {
                proStatusManager.finishOnboardingWithoutTrial()
                onFinish()
            }
            .disabled(isBusy)

            DSDotSeparator()

            Button("Terms") { openExternalURL(ExternalLinks.termsURL) }

            DSDotSeparator()

            Button("Privacy") { openExternalURL(ExternalLinks.privacyURL) }
        }
        .buttonStyle(.link)
        .font(.caption)
    }

    private var purchaseCTA: String {
        guard selectedProduct.isAvailable else { return "Unavailable" }
        return "Get \(selectedProduct.title) — \(selectedProduct.displayPrice)"
    }

    private func purchaseSelectedPlan() async {
        guard selectedProduct.isAvailable else { return }
        isPurchasingLifetime = true
        defer { isPurchasingLifetime = false }

        do {
            try await proStatusManager.purchase(selectedPlan)
            if proStatusManager.status.isPro {
                onFinish()
            }
        } catch {
            if (error as? ProPurchaseError) != .purchaseCancelled {
                AppLogger.purchase.error("Onboarding purchase failed: \(error.localizedDescription)")
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

private enum OnboardingLayout {
    static let titlebarInset: CGFloat = 12
    static let topPadding: CGFloat = 48 + titlebarInset
    static let bottomPadding: CGFloat = 36
    static let heroHeight: CGFloat = 88
    static let contentHorizontalPadding: CGFloat = 100
    static let paywallHorizontalPadding: CGFloat = 120
    static let primaryButtonWidth: CGFloat = 200
    static let diagramHorizontalPadding: CGFloat = 60
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
                .background(Circle().fill(DS.Colors.brandPrimary))

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

private struct OnboardingPlanCard: View {
    let product: ProPlanProduct
    let isSelected: Bool
    var onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: DS.Spacing.xs) {
                Text(product.title.uppercased())
                    .font(DS.Typography.microSemibold)
                    .foregroundStyle(isSelected ? DS.Colors.brandPrimary : .secondary)
                    .lineLimit(1)

                Text(product.displayPrice)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)

                Text(product.billingDetail)
                    .font(DS.Typography.micro)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 82)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                    .fill(isSelected ? DS.Colors.brandPrimary.opacity(0.06) : Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                    .strokeBorder(
                        isSelected ? DS.Colors.brandPrimary.opacity(0.5) : DS.Colors.cardBorder,
                        lineWidth: isSelected ? 1.5 : 0.5
                    )
            )
        }
        .buttonStyle(.plain)
        .opacity(product.isAvailable ? 1 : 0.45)
        .disabled(!product.isAvailable)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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
                label: "⌘ Tab",
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
                    .font(DS.Typography.captionMedium)
                Text(sublabel)
                    .font(DS.Typography.micro)
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

private struct PaywallBenefitRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: DS.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(DS.Colors.brandPrimary)
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
                initialTab: .general
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
