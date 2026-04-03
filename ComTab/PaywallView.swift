//
//  PaywallView.swift
//  ComTab
//
//  Created by CHEN on 2026/3/28.
//

import AppKit
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
    let entitlementSnapshot: ProEntitlementSnapshot?
    let isPreviewing: Bool
    let showsStatusChip: Bool

    static func live(
        status: ProStatus,
        entitlementSnapshot: ProEntitlementSnapshot?
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
    @State private var selectedPlan: ProPlan = .lifetime
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
                        .font(DS.Typography.caption)
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
                    .font(DS.Typography.caption)
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
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
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
                backgroundColor: isExpired ? DS.Colors.warningFill : DS.Colors.accentTint,
                size: 42,
                iconSize: 18
            )
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                Text("Reopen Pro")
                    .font(DS.Typography.headlineMedium)
                Text(statusSubtitle)
                    .font(DS.Typography.caption)
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
                        Text(badge)
                            .font(DS.Typography.microSemibold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, DS.Spacing.xxs)
                            .background(
                                Capsule().fill(
                                    LinearGradient(
                                        colors: [.accentColor, Color.accentColor.opacity(0.7)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                            )
                    }
                    if !product.isAvailable {
                        Text("Unavailable")
                            .font(DS.Typography.microSemibold)
                            .foregroundColor(.secondary)
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
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .fill(isSelected ? DS.Colors.accentTintSubtle : Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
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
                Text(ctaText).font(DS.Typography.bodyLarge)

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
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
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
            .font(DS.Typography.caption)
            .disabled(isBusy)

            DSDotSeparator()

            Button("Terms") { openExternalURL(ExternalLinks.termsURL) }
                .buttonStyle(.link)
                .font(DS.Typography.caption)

            DSDotSeparator()

            Button("Privacy") { openExternalURL(ExternalLinks.privacyURL) }
                .buttonStyle(.link)
                .font(DS.Typography.caption)
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

                Divider()
                    .padding(.horizontal, DS.Spacing.lg)

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

    private func proHeader(plan: ProPlan) -> some View {
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

                    Text(plan == .lifetime ? "Lifetime" : "Yearly")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, DS.Spacing.sm)
                        .padding(.vertical, 3)
                        .background(
                            Capsule().fill(DS.Colors.proFill)
                        )
                }

                Text("All features unlocked — thank you for your support.")
                    .font(DS.Typography.caption)
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
                .font(DS.Typography.bodySmall)
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



private struct ProLetterView: View {
    let displayState: ProDisplayState

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.lg) {
            // Small caps label
            Text(labelText)
                .font(DS.Typography.letterLabel)
                .tracking(0.8)
                .foregroundColor(.accentColor.opacity(0.55))

            // Editorial headline
            Text(headline)
                .font(DS.Typography.letterHeadline)
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)

            // Body — relaxed, lighter
            Text(bodyText)
                .font(DS.Typography.letterBody)
                .foregroundColor(.primary.opacity(0.62))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)

            // Signature — medium, distinct from body
            Text(signature)
                .font(DS.Typography.letterSignature)
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
            return "You came in with \(days == 7 ? "7 days" : "\(days) day\(days == 1 ? "" : "s")") free. Use them."
        case .expired:
            return "Your 7 days are up."
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
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .fill(Color(nsColor: .systemGreen).opacity(0.09))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .stroke(Color(nsColor: .systemGreen).opacity(0.18), lineWidth: 1)
            )
    }

#if DEBUG
    private var previewPicker: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            Picker("UI 预览", selection: $previewMode) {
                ForEach(ProPreviewMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Text("仅用于临时查看 UI 状态")
                .font(DS.Typography.caption)
                .foregroundColor(.secondary)

            Button("触发 Onboarding") {
                OnboardingWindowController.shared.show(proStatusManager: proStatusManager)
            }
            .buttonStyle(.link)
            .font(DS.Typography.captionMedium)
        }
    }
#endif
}
