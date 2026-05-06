//
//  PaywallView.swift
//  CmdReopen
//
//  Created by CHEN on 2026/3/28.
//

import AppKit
import ConfettiSwiftUI
import RevenueCatCommerceKit
import SwiftUI
import os

enum ProPreviewMode: String, CaseIterable, Identifiable {
    case live
    case notPro
    case yearlyPro
    case lifetimePro

    var id: String { rawValue }

    var title: String {
        switch self {
        case .live: return "真实状态"
        case .notPro: return "未开通"
        case .yearlyPro: return "年度 Pro"
        case .lifetimePro: return "永久 Pro"
        }
    }
}

struct ProDisplayState {
    let status: ProStatus
    let entitlementSnapshot: CommerceEntitlement?
    let isPreviewing: Bool
    let showsStatusChip: Bool

    static func live(
        status: ProStatus,
        entitlementSnapshot: CommerceEntitlement?
    ) -> Self {
        .init(
            status: status,
            entitlementSnapshot: entitlementSnapshot,
            isPreviewing: false,
            showsStatusChip: true
        )
    }

    static func preview(_ mode: ProPreviewMode, now: Date = Date()) -> Self {
        let purchaseDate = Calendar.current.date(byAdding: .day, value: -120, to: now)
        let yearlyExpirationDate = Calendar.current.date(byAdding: .day, value: 365, to: now)

        switch mode {
        case .live:
            fatalError("Use live(status:entitlementSnapshot:) for live display state.")
        case .notPro:
            return .init(
                status: .expired,
                entitlementSnapshot: nil,
                isPreviewing: true,
                showsStatusChip: false
            )
        case .yearlyPro:
            return .init(
                status: .pro(plan: .yearly, expirationDate: yearlyExpirationDate, willRenew: true),
                entitlementSnapshot: .init(
                    plan: .yearly,
                    productIdentifier: RevenueCatConfiguration.yearlyProductIdentifier,
                    entitlementIdentifier: RevenueCatConfiguration.entitlementIdentifier,
                    expirationDate: yearlyExpirationDate,
                    willRenew: true,
                    originalPurchaseDate: purchaseDate
                ),
                isPreviewing: true,
                showsStatusChip: false
            )
        case .lifetimePro:
            return .init(
                status: .pro(plan: .lifetime, expirationDate: nil, willRenew: false),
                entitlementSnapshot: .init(
                    plan: .lifetime,
                    productIdentifier: RevenueCatConfiguration.lifetimeProductIdentifier,
                    entitlementIdentifier: RevenueCatConfiguration.entitlementIdentifier,
                    expirationDate: nil,
                    willRenew: false,
                    originalPurchaseDate: purchaseDate
                ),
                isPreviewing: true,
                showsStatusChip: false
            )
        }
    }
}

// MARK: - Upgrade Card (shown when trial or expired)

struct UpgradeCardView: View {
    @EnvironmentObject private var proStatusManager: ProStatusManager
    @EnvironmentObject private var reopenStatsStore: ReopenStatsStore
    let displayState: ProDisplayState
    @State private var selectedPlan: CommercePlan = .lifetime
    @State private var isLoadingOfferings = false

    private var displayStatus: ProStatus { displayState.status }

    private var isExpired: Bool { displayStatus == .expired }

    private var selectedProduct: ProPlanProduct {
        proStatusManager.planProduct(for: selectedPlan)
    }

    private var isPurchasingSelectedPlan: Bool {
        proStatusManager.purchaseInProgressPlan == selectedPlan
    }

    private var isBusy: Bool {
        proStatusManager.purchaseInProgressPlan != nil
            || proStatusManager.isRestoringPurchases
    }

    var body: some View {
        VStack(spacing: 0) {
            // Tinted header — mirrors ProStatusBadgeView layout
            heroSection
                .padding(.horizontal, DS.Spacing.xl)
                .padding(.top, DS.Spacing.xl)
                .padding(.bottom, DS.Spacing.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(isExpired ? DS.Colors.warningTint : DS.Colors.accentTintSubtle)

            Divider()

            // Stats-based nudge for expired users
            if isExpired, reopenStatsStore.totalSuccessfulReopens > 0 {
                HStack(spacing: DS.Spacing.sm) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.orange)
                    Text("Command Reopen helped you **\(reopenStatsStore.totalSuccessfulReopens) times** during your trial.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, DS.Spacing.xl)
                .padding(.top, DS.Spacing.md)
            }

            // Plans
            VStack(spacing: DS.Spacing.sm) {
                ForEach(proStatusManager.availablePlans) { product in
                    planRow(product: product)
                }
            }
            .padding(.horizontal, DS.Spacing.xl)
            .padding(.top, DS.Spacing.md)
            .padding(.bottom, DS.Spacing.sm)

            if let paywallErrorMessage = proStatusManager.paywallErrorMessage {
                Text(paywallErrorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, DS.Spacing.xl)
                    .padding(.bottom, DS.Spacing.xs)
            }

            ctaButton
                .padding(.horizontal, DS.Spacing.xl)
                .padding(.vertical, DS.Spacing.sm)

            footerLinks
                .padding(.bottom, DS.Spacing.lg)
        }
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
        .dsCard()
        .task {
            isLoadingOfferings = true
            await proStatusManager.loadOfferings()
            syncSelectedPlan()
            isLoadingOfferings = false
        }
        .modifier(OnChangeCompat(value: proStatusManager.availablePlans) {
            syncSelectedPlan()
        })
    }

    // MARK: - Hero (mirrors ProStatusBadgeView proHeader layout)

    private var heroSection: some View {
        HStack(spacing: DS.Spacing.md) {
            DSIconBadge(
                systemName: isExpired ? "exclamationmark.triangle.fill" : "checkmark.seal.fill",
                iconColor: isExpired ? .orange : .accentColor,
                backgroundColor: isExpired ? DS.Colors.warningTint : DS.Colors.accentTint,
                size: 42,
                iconSize: 18
            )
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                Text("Reopen Pro")
                    .font(DS.Typography.headlineMedium)
                Text(statusSubtitle)
                    .font(.caption)
                    .foregroundColor(statusSubtitleColor)
            }
            Spacer(minLength: 0)
        }
    }

    private var statusSubtitle: String {
        switch displayStatus {
        case .expired:
            return "Your trial has ended"
        case .trial(let days, _):
            return "\(days) day\(days == 1 ? "" : "s") left in your free trial"
        case .pro:
            return ""
        }
    }

    private var statusSubtitleColor: Color {
        switch displayStatus {
        case .expired:
            return .orange.opacity(0.85)
        case .trial(let days, _) where days <= 2:
            return .orange.opacity(0.85)
        default:
            return .secondary
        }
    }

    // MARK: - Status Chip (removed — status is now shown in heroSection subtitle)

    // MARK: - Plan Row

    private func planRow(product: ProPlanProduct) -> some View {
        let isSelected = selectedPlan == product.plan

        return Button {
            guard product.isAvailable, !isBusy else { return }
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedPlan = product.plan
            }
        } label: {
            HStack(spacing: DS.Spacing.md) {
                ZStack {
                    Circle()
                        .stroke(
                            isSelected ? Color.accentColor : Color(nsColor: .separatorColor),
                            lineWidth: 1.5
                        )
                        .frame(width: 18, height: 18)
                    if isSelected {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 8, height: 8)
                    }
                }

                HStack(spacing: 6) {
                    Text(product.title)
                        .font(DS.Typography.bodyMedium)
                    if let badge = product.badge {
                        StatusPill(text: badge, tone: .accent)
                    }
                    if !product.isAvailable {
                        StatusPill(text: "Unavailable", tone: .neutral)
                    }
                }

                Spacer()

                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(product.displayPrice)
                        .font(DS.Typography.headlineSmall)
                        .foregroundColor(isSelected ? .accentColor : .primary)
                    Text(product.plan == .lifetime ? "once" : "year")
                        .font(DS.Typography.captionMedium)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.vertical, DS.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                    .fill(isSelected ? DS.Colors.accentTintSubtle : Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                    .stroke(
                        isSelected ? Color.accentColor.opacity(0.5) : DS.Colors.cardBorder,
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
            .opacity(product.isAvailable ? 1 : 0.5)
        }
        .buttonStyle(.plain)
        .disabled(!product.isAvailable || isBusy)
    }

    // MARK: - CTA Button

    private var ctaButton: some View {
        Button {
            Task { await purchaseSelectedPlan() }
        } label: {
            HStack(spacing: DS.Spacing.sm) {
                if isPurchasingSelectedPlan {
                    ProgressView().controlSize(.small).tint(.white)
                } else {
                    Image(systemName: "lock.open.fill")
                        .font(.system(size: 12))
                }
                Text(ctaText).font(.headline)

                if isLoadingOfferings {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                }
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                    .fill(LinearGradient(
                        colors: ctaGradientColors,
                        startPoint: .leading,
                        endPoint: .trailing
                    ))
            )
        }
        .buttonStyle(.plain)
        .disabled(isBusy || !selectedProduct.isAvailable)
        .opacity(isBusy || !selectedProduct.isAvailable ? 0.7 : 1)
    }

    // MARK: - Footer Links

    private var footerLinks: some View {
        HStack(spacing: DS.Spacing.md) {
            Button(proStatusManager.isRestoringPurchases ? "Restoring..." : "Restore Purchase") {
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

    // MARK: - Helpers

    private var ctaText: String {
        guard selectedProduct.isAvailable else { return "Currently Unavailable" }
        switch selectedPlan {
        case .yearly:   return "Subscribe — \(selectedProduct.displayPrice)/year"
        case .lifetime: return "Unlock Forever — \(selectedProduct.displayPrice)"
        }
    }

    private var ctaGradientColors: [Color] {
        selectedProduct.isAvailable
            ? [Color.accentColor, Color.accentColor.opacity(0.75)]
            : [Color.secondary.opacity(0.7), Color.secondary.opacity(0.5)]
    }

    private func syncSelectedPlan() {
        if proStatusManager.planProduct(for: selectedPlan).isAvailable { return }
        if let firstAvailablePlan = proStatusManager.availablePlans.first(where: { $0.isAvailable })?.plan {
            selectedPlan = firstAvailablePlan
        }
    }

    private func purchaseSelectedPlan() async {
        guard selectedProduct.isAvailable else { return }

        do {
            try await proStatusManager.purchase(selectedPlan)
        } catch {
            if (error as? ProPurchaseError) != .purchaseCancelled {
                AppLogger.purchase.error("Purchase failed: \(error.localizedDescription)")
            }
        }
    }

    private func restorePurchases() async {
        do {
            try await proStatusManager.restorePurchases()
        } catch {
            if (error as? ProPurchaseError) != .purchaseCancelled {
                AppLogger.purchase.error("Restore failed: \(error.localizedDescription)")
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

// MARK: - Pro Status Badge (shown when already purchased)

struct ProStatusBadgeView: View {
    @EnvironmentObject private var proStatusManager: ProStatusManager
    let displayState: ProDisplayState

    var body: some View {
        if case .pro(let plan, _, _) = displayState.status {
            VStack(spacing: 0) {
                proHeader(plan: plan)
                    .padding(.horizontal, DS.Spacing.xl)
                    .padding(.top, DS.Spacing.xl)
                    .padding(.bottom, DS.Spacing.lg)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(DS.Colors.accentTintSubtle)

                Divider()

                metadataSection
                    .padding(.horizontal, DS.Spacing.xl)
                    .padding(.vertical, DS.Spacing.lg)

                if plan == .yearly {
                    Divider()
                        .padding(.horizontal, DS.Spacing.lg)

                    HStack {
                        Button("Manage Subscription") {
                            openManageSubscription()
                        }
                        .buttonStyle(.link)
                        .font(DS.Typography.captionMedium)

                        Spacer()
                    }
                    .padding(.horizontal, DS.Spacing.xl)
                    .padding(.vertical, DS.Spacing.md)
                }
            }
            .dsCard()
        }
    }

    private func proHeader(plan: CommercePlan) -> some View {
        HStack(spacing: DS.Spacing.md) {
            DSIconBadge(
                systemName: "checkmark.seal.fill",
                iconColor: .accentColor,
                backgroundColor: DS.Colors.accentTint,
                size: 42,
                iconSize: 18
            )

            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                HStack(spacing: DS.Spacing.sm) {
                    Text("Pro")
                        .font(DS.Typography.headlineMedium)

                    StatusPill(text: plan == .lifetime ? "Lifetime" : "Yearly", tone: .accent)
                }

                Text("All features unlocked — thank you for your support.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer(minLength: 0)
        }
    }

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            if let purchaseDate = displayState.entitlementSnapshot?.originalPurchaseDate {
                metadataRow(label: "Member since", value: formattedDate(purchaseDate))
            }

            if let renewalState = displayState.status.renewalState {
                metadataRow(label: renewalLabel(for: renewalState), value: renewalDate(for: renewalState))
            }
        }
    }

    private func metadataRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.md) {
            Text(label)
                .font(DS.Typography.captionMedium)
                .foregroundColor(.secondary)
                .frame(width: 86, alignment: .leading)

            Text(value)
                .font(.callout)
                .foregroundColor(.primary)

            Spacer()
        }
    }

    private func renewalLabel(for renewalState: ProRenewalState) -> String {
        switch renewalState {
        case .renews: return "Renews"
        case .ends:   return "Ends"
        }
    }

    private func renewalDate(for renewalState: ProRenewalState) -> String {
        switch renewalState {
        case .renews(let date, _), .ends(let date, _):
            return formattedDate(date)
        }
    }

    private func formattedDate(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day().year())
    }

    private func openManageSubscription() {
        guard let url = URL(string: AppStoreLinks.manageSubscriptionsURL) else { return }
        NSWorkspace.shared.open(url)
    }
}

// MARK: - Paywall Sheet

enum PaywallPresentationContext {
    case onboarding
    case settings
}

struct PaywallSheetView: View {
    @ObservedObject var proStatusManager: ProStatusManager
    let context: PaywallPresentationContext
    var onFinish: () -> Void = {}
    var reopenStatsStore: ReopenStatsStore = .shared

    @Environment(\.dismiss) private var dismiss
    @State private var selectedPlan: CommercePlan = .lifetime
    @State private var isLoadingOfferings = false
    @State private var isStartingTrial = false
    @State private var confettiTrigger = 0

    private var displayState: ProDisplayState {
        .live(
            status: proStatusManager.status,
            entitlementSnapshot: proStatusManager.currentEntitlementSnapshot
        )
    }

    private var selectedProduct: ProPlanProduct {
        proStatusManager.planProduct(for: selectedPlan)
    }

    private var isBusy: Bool {
        isLoadingOfferings
            || isStartingTrial
            || proStatusManager.purchaseInProgressPlan != nil
            || proStatusManager.isRestoringPurchases
    }

    private var isOnboarding: Bool {
        context == .onboarding
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: DS.Spacing.md) {
                        sheetHeader
                            .padding(.top, DS.Spacing.sm)

                        if displayState.status.isPro {
                            ProStatusBadgeView(displayState: displayState)
                                .environmentObject(proStatusManager)
                        } else {
                            statsStrip
                            benefits
                            planPicker
                            messageStack
                        }
                    }
                    .padding(.horizontal, sheetPadding)
                    .padding(.bottom, DS.Spacing.md)
                }

                VStack(spacing: DS.Spacing.sm) {
                    if !displayState.status.isPro {
                        actionStack
                    }
                    footer
                }
                .padding(.horizontal, sheetPadding)
                .padding(.bottom, DS.Spacing.md)
            }

            if !isOnboarding {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20, weight: .medium))
                        .symbolRenderingMode(.hierarchical)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .padding(DS.Spacing.lg)
                .accessibilityLabel("Close")
            }
        }
        .frame(width: sheetWidth, height: sheetHeight)
        .background {
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                RadialGradient(
                    colors: [DS.Colors.brandPrimary.opacity(0.05), .clear],
                    center: .top,
                    startRadius: 0,
                    endRadius: 350
                )
            }
        }
        .task {
            guard !isLoadingOfferings else { return }
            isLoadingOfferings = true
            await proStatusManager.loadOfferings()
            syncSelectedPlan()
            isLoadingOfferings = false
        }
        .modifier(OnChangeCompat(value: proStatusManager.availablePlans) {
            syncSelectedPlan()
        })
        .interactiveDismissDisabled(isOnboarding)
        .confettiCannon(
            trigger: $confettiTrigger,
            num: 50,
            confettis: [.shape(.circle), .shape(.roundedCross)],
            colors: [DS.Colors.brandPrimary, .orange, .purple, .pink],
            confettiSize: 8,
            rainHeight: 500,
            radius: 300
        )
    }

    private var sheetWidth: CGFloat {
        isOnboarding ? 560 : 500
    }

    private var sheetHeight: CGFloat {
        isOnboarding ? 620 : 520
    }

    private var sheetPadding: CGFloat {
        isOnboarding ? DS.Spacing.xxl : DS.Spacing.xl
    }

    private var sheetHeader: some View {
        VStack(spacing: DS.Spacing.md) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 80, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: .black.opacity(0.10), radius: 10, y: 5)

            Text("Choose your plan")
                .font(DS.Typography.onboardingTitle)
                .multilineTextAlignment(.center)

            Text(headerSubtitle)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var statsStrip: some View {
        let totalReopens = reopenStatsStore.totalSuccessfulReopens
        let topApps = reopenStatsStore.topApps(3)
        if totalReopens > 0 {
            HStack(spacing: DS.Spacing.lg) {
                PaywallStatItem(
                    value: "\(totalReopens)",
                    label: "windows reopened"
                )
                if let topApp = topApps.first {
                    PaywallStatItem(
                        value: topApp.displayName,
                        label: "\(topApp.count) reopens"
                    )
                }
            }
            .padding(.vertical, DS.Spacing.sm)
            .padding(.horizontal, DS.Spacing.lg)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                    .fill(DS.Colors.brandPrimary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                    .strokeBorder(DS.Colors.brandPrimary.opacity(0.12), lineWidth: 0.5)
            )
        }
    }

    private var benefits: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            PaywallFeatureRow(icon: "checkmark.circle", text: "Never lose a minimized window again")
            PaywallFeatureRow(icon: "checkmark.circle", text: "Keep Command-Tab focused and predictable")
            PaywallFeatureRow(icon: "checkmark.circle", text: "Exclude apps that should stay quiet")
        }
        .frame(maxWidth: 360, alignment: .leading)
    }

    private var planPicker: some View {
        HStack(spacing: DS.Spacing.sm) {
            ForEach(proStatusManager.availablePlans) { product in
                PaywallPlanCard(
                    product: product,
                    isSelected: selectedPlan == product.plan,
                    onSelect: { selectedPlan = product.plan }
                )
            }
        }
        .animation(.easeInOut(duration: 0.15), value: selectedPlan)
    }

    @ViewBuilder
    private var messageStack: some View {
        VStack(spacing: DS.Spacing.xs) {
            if isLoadingOfferings {
                Text("Loading purchase options...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let paywallErrorMessage = proStatusManager.paywallErrorMessage {
                Text(paywallErrorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let successMessage = proStatusManager.paywallSuccessMessage {
                Text(successMessage)
                    .font(DS.Typography.captionMedium)
                    .foregroundColor(Color(nsColor: .systemGreen))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var actionStack: some View {
        VStack(spacing: DS.Spacing.sm) {
            Button {
                Task { await purchaseSelectedPlan() }
            } label: {
                PaywallActionLabel(
                    title: purchaseCTA,
                    isLoading: proStatusManager.purchaseInProgressPlan == selectedPlan,
                    isProminent: true
                )
            }
            .buttonStyle(.plain)
            .disabled(isBusy || !selectedProduct.isAvailable)
            .opacity(isBusy || !selectedProduct.isAvailable ? 0.45 : 1)

            if isOnboarding {
                Button {
                    Task { await startTrial() }
                } label: {
                    PaywallActionLabel(
                        title: "Start 2-Day Free Trial",
                        isLoading: isStartingTrial,
                        isProminent: false
                    )
                }
                .buttonStyle(.plain)
                .disabled(isBusy)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: DS.Spacing.md) {
            Button(proStatusManager.isRestoringPurchases ? "Restoring..." : "Restore Purchase") {
                Task { await restorePurchases() }
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

    private var headerSubtitle: String {
        switch displayState.status {
        case .pro:
            return "All features are unlocked."
        case .trial(let daysRemaining, let expiresAt):
            if isOnboarding {
                return "Choose yearly or lifetime access, or start your trial."
            }
            return "\(daysRemaining) day\(daysRemaining == 1 ? "" : "s") left in your trial, expires \(formattedDate(expiresAt))."
        case .expired:
            return "Your trial has ended. Upgrade to keep Command Reopen active."
        }
    }

    private var purchaseCTA: String {
        guard selectedProduct.isAvailable else { return "Unavailable" }
        switch selectedPlan {
        case .yearly:
            return "Subscribe - \(selectedProduct.displayPrice)"
        case .lifetime:
            return "Unlock Forever - \(selectedProduct.displayPrice)"
        }
    }

    private func syncSelectedPlan() {
        if proStatusManager.planProduct(for: selectedPlan).isAvailable { return }
        if let firstAvailablePlan = proStatusManager.availablePlans.first(where: { $0.isAvailable })?.plan {
            selectedPlan = firstAvailablePlan
        }
    }

    private func purchaseSelectedPlan() async {
        guard selectedProduct.isAvailable else { return }

        do {
            try await proStatusManager.purchase(selectedPlan)
            if proStatusManager.status.isPro {
                finishSuccessfulPaidAction()
            }
        } catch {
            if (error as? ProPurchaseError) != .purchaseCancelled {
                AppLogger.purchase.error("Paywall purchase failed: \(error.localizedDescription)")
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
        do {
            try await proStatusManager.restorePurchases()
            if proStatusManager.status.isPro {
                if isOnboarding {
                    proStatusManager.finishOnboardingWithoutTrial()
                }
                finishSuccessfulPaidAction()
            }
        } catch {
            if (error as? ProPurchaseError) != .purchaseCancelled {
                AppLogger.purchase.error("Paywall restore failed: \(error.localizedDescription)")
            }
        }
    }

    private func finishSuccessfulPaidAction() {
        confettiTrigger += 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            if isOnboarding {
                onFinish()
            } else {
                dismiss()
                onFinish()
            }
        }
    }

    private func openExternalURL(_ urlString: String) {
        guard let url = URL(string: urlString) else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    private func formattedDate(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day().year())
    }
}

private struct PaywallStatItem: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: DS.Spacing.xxs) {
            Text(value)
                .font(DS.Typography.headlineSmall)
                .foregroundStyle(DS.Colors.brandPrimary)
                .lineLimit(1)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct PaywallFeatureRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: DS.Spacing.sm) {
            Image(systemName: icon)
                .foregroundStyle(DS.Colors.brandPrimary)
                .frame(width: 18)
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }
}

private struct PaywallPlanCard: View {
    let product: ProPlanProduct
    let isSelected: Bool
    let onSelect: () -> Void

    private var originalPrice: String {
        switch product.plan {
        case .yearly: return "$7.99"
        case .lifetime: return "$14.99"
        }
    }

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: DS.Spacing.sm) {
                if let badge = product.badge {
                    Text(badge)
                        .font(DS.Typography.microSemibold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, DS.Spacing.sm)
                        .padding(.vertical, DS.Spacing.xxs)
                        .background(Capsule().fill(DS.Colors.brandPrimary))
                } else {
                    Text(product.title)
                        .font(DS.Typography.microSemibold)
                        .foregroundStyle(.secondary)
                }

                HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.xs) {
                    Text(originalPrice)
                        .font(.callout)
                        .strikethrough()
                        .foregroundStyle(.secondary)
                    Text(product.displayPrice)
                        .font(DS.Typography.headlineSmall)
                        .foregroundStyle(.primary)
                }

                Text(product.billingDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, DS.Spacing.md)
            .padding(.horizontal, DS.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                    .fill(isSelected ? DS.Colors.brandPrimary.opacity(0.06) : Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                    .strokeBorder(isSelected ? DS.Colors.brandPrimary : DS.Colors.cardBorder, lineWidth: isSelected ? 1.5 : 0.5)
            )
        }
        .buttonStyle(.plain)
        .disabled(!product.isAvailable)
        .opacity(product.isAvailable ? 1 : 0.45)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}

private struct PaywallActionLabel: View {
    let title: String
    let isLoading: Bool
    let isProminent: Bool

    var body: some View {
        HStack(spacing: DS.Spacing.sm) {
            if isLoading {
                ProgressView()
                    .controlSize(.small)
            }

            Text(title)
                .font(.headline)
        }
        .foregroundStyle(isProminent ? .white : .primary)
        .frame(maxWidth: .infinity)
        .frame(height: 44)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .fill(isProminent ? DS.Colors.brandPrimary : Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .strokeBorder(isProminent ? Color.clear : DS.Colors.cardBorder, lineWidth: 0.5)
        )
    }
}



private struct ProLetterView: View {
    let displayState: ProDisplayState

    private enum LetterFont {
        static let label     = Font.system(size: 12, weight: .semibold)
        static let headline  = Font.system(size: 18, weight: .regular)
        static let body      = Font.body
        static let signature = Font.system(size: 14, weight: .medium)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.lg) {
            Text(labelText)
                .font(LetterFont.label)
                .tracking(0.8)
                .foregroundColor(.accentColor.opacity(0.55))

            Text(headline)
                .font(LetterFont.headline)
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Text(bodyText)
                .font(LetterFont.body)
                .foregroundColor(.primary.opacity(0.62))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)

            Text(signature)
                .font(LetterFont.signature)
                .foregroundColor(.primary.opacity(0.5))
                .padding(.top, DS.Spacing.xxs)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DS.Spacing.xs)
    }

    private var labelText: String {
        displayState.status.isPro ? "A NOTE FROM CHEN" : "BEFORE YOU DECIDE"
    }

    private var headline: String {
        switch displayState.status {
        case .pro:
            return "Thank you for being here."
        case .trial(let days, _):
            return "You came in with \(days == 2 ? "2 days" : "\(days) day\(days == 1 ? "" : "s")") free. Use them."
        case .expired:
            return "Your 2 days are up."
        }
    }

    private var bodyText: String {
        switch displayState.status {
        case .pro:
            return "Your support keeps this app small and honest — no bloat, no noise. I hope it keeps showing up for you, quietly, every time you need it."
        case .trial:
            return "Every Cmd+Tab should bring your window back. That's the only thing this app does — and you have a full week to test that claim, with everything unlocked.\n\nIf it holds up, I hope you'll stick around."
        case .expired:
            return "You've had a full week with everything unlocked. If Command Reopen made your workflow a little smoother, I hope you'll keep it.\n\nIf it didn't, no hard feelings."
        }
    }

    private var signature: String {
        displayState.status.isPro ? "With thanks,\nChen" : "Warmly,\nChen"
    }
}

// MARK: - Combined Pro Section

struct ProSectionView: View {
    @EnvironmentObject private var proStatusManager: ProStatusManager
    @State private var previewMode: ProPreviewMode = .live

    private var displayState: ProDisplayState {
        switch previewMode {
        case .live:
            return .live(
                status: proStatusManager.status,
                entitlementSnapshot: proStatusManager.currentEntitlementSnapshot
            )
        case .notPro, .yearlyPro, .lifetimePro:
            return .preview(previewMode)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xxl) {
            if let successMessage = proStatusManager.paywallSuccessMessage, previewMode == .live {
                successBanner(message: successMessage)
            }

            if displayState.status.isPro {
                ProStatusBadgeView(displayState: displayState)
            } else {
                UpgradeCardView(displayState: displayState)
            }

            ProLetterView(displayState: displayState)

#if DEBUG
            previewPicker
#endif
        }
    }

    private func successBanner(message: String) -> some View {
        Text(message)
            .font(DS.Typography.captionMedium)
            .foregroundColor(Color(nsColor: .systemGreen))
            .padding(.horizontal, DS.Spacing.md)
            .padding(.vertical, DS.Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                    .fill(Color(nsColor: .systemGreen).opacity(0.09))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                    .stroke(Color(nsColor: .systemGreen).opacity(0.18), lineWidth: 1)
            )
    }

#if DEBUG
    private var previewPicker: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            Picker("UI Preview", selection: $previewMode) {
                ForEach(ProPreviewMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Text("Temporary UI state preview only")
                .font(.caption)
                .foregroundColor(.secondary)

            Button("Trigger Onboarding") {
                OnboardingWindowController.shared.show(proStatusManager: proStatusManager)
            }
            .buttonStyle(.link)
            .font(DS.Typography.captionMedium)
        }
    }
#endif
}
