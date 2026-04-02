//
//  PaywallView.swift
//  ComTab
//
//  Created by CHEN on 2026/3/28.
//

import AppKit
import SwiftUI
import os

private let proFeatureItems: [(String, String)] = [
    ("arrow.clockwise", "Auto-reopen windows"),
    ("slider.horizontal.3", "Per-app exclusion"),
    ("chart.bar", "Statistics & insights"),
    ("arrow.up.circle", "Future updates")
]

// MARK: - Upgrade Card (shown when trial or expired)

struct UpgradeCardView: View {
    @EnvironmentObject private var proStatusManager: ProStatusManager
    @State private var selectedPlan: ProPlan = .lifetime
    @State private var isLoadingOfferings = false

    private var isExpired: Bool {
        proStatusManager.status == .expired
    }

    private var selectedProduct: ProPlanProduct {
        proStatusManager.planProduct(for: selectedPlan)
    }

    private var isPurchasingSelectedPlan: Bool {
        proStatusManager.purchaseInProgressPlan == selectedPlan
    }

    private var isBusy: Bool {
        proStatusManager.purchaseInProgressPlan != nil || proStatusManager.isRestoringPurchases || isLoadingOfferings
    }

    var body: some View {
        VStack(spacing: 0) {
            statusBanner
                .padding(.horizontal, DS.Spacing.xl)
                .padding(.top, DS.Spacing.xxl)
                .padding(.bottom, DS.Spacing.xl)

            featuresGrid
                .padding(.horizontal, DS.Spacing.xl)
                .padding(.bottom, DS.Spacing.xl)

            Divider()
                .padding(.horizontal, DS.Spacing.lg)

            Group {
                if isLoadingOfferings {
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DS.Spacing.xl)
                } else {
                    VStack(spacing: DS.Spacing.md) {
                        ForEach(proStatusManager.availablePlans) { product in
                            planRow(product: product)
                        }
                    }
                }
            }
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.vertical, 18)

            if let paywallErrorMessage = proStatusManager.paywallErrorMessage {
                Text(paywallErrorMessage)
                    .font(DS.Typography.caption)
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, DS.Spacing.lg)
                    .padding(.bottom, 10)
            }

            Button {
                Task {
                    await purchaseSelectedPlan()
                }
            } label: {
                HStack(spacing: DS.Spacing.sm) {
                    if isPurchasingSelectedPlan {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                    } else {
                        Image(systemName: "lock.open.fill")
                            .font(.system(size: 12))
                    }

                    Text(ctaText)
                        .font(DS.Typography.bodyLarge)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: ctaGradientColors,
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                )
            }
            .buttonStyle(.plain)
            .disabled(isBusy || !selectedProduct.isAvailable)
            .opacity(isBusy || !selectedProduct.isAvailable ? 0.7 : 1)
            .padding(.horizontal, DS.Spacing.lg)
            .padding(.bottom, DS.Spacing.lg)

            HStack(spacing: 10) {
                Button(proStatusManager.isRestoringPurchases ? "Restoring..." : "Restore Purchase") {
                    Task {
                        await restorePurchases()
                    }
                }
                .buttonStyle(.link)
                .font(DS.Typography.caption)
                .disabled(isBusy)

                DSDotSeparator()

                Button("Terms") {
                    openExternalURL(ExternalLinks.officialURL)
                }
                .buttonStyle(.link)
                .font(DS.Typography.caption)

                DSDotSeparator()

                Button("Privacy") {
                    openExternalURL(ExternalLinks.officialURL)
                }
                .buttonStyle(.link)
                .font(DS.Typography.caption)
            }
            .padding(.bottom, DS.Spacing.xl)
        }
        .dsCard(borderColor: cardBorder)
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

    // MARK: - Status Banner

    private var statusBanner: some View {
        HStack(spacing: 10) {
            DSIconBadge(
                systemName: isExpired ? "exclamationmark.triangle.fill" : "clock.fill",
                iconColor: isExpired ? .orange : .accentColor,
                backgroundColor: isExpired ? DS.Colors.warningTint : DS.Colors.accentTint,
                size: 36,
                iconSize: 16
            )

            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                if isExpired {
                    Text("Trial Expired")
                        .font(DS.Typography.bodyLarge)
                    Text("Purchased on another Mac? Tap Restore below.")
                        .font(DS.Typography.caption)
                        .foregroundColor(.secondary)
                } else if case .trial(let days, _) = proStatusManager.status {
                    Text("Pro Trial")
                        .font(DS.Typography.bodyLarge)
                    Text("\(days) day\(days == 1 ? "" : "s") remaining")
                        .font(DS.Typography.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            if case .trial(let days, _) = proStatusManager.status {
                trialProgressRing(daysRemaining: days)
            }
        }
    }

    private func trialProgressRing(daysRemaining: Int) -> some View {
        let progress = Double(7 - daysRemaining) / 7.0

        return ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.15), lineWidth: 3)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    daysRemaining <= 2 ? Color.orange : Color.accentColor,
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            Text("\(daysRemaining)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(daysRemaining <= 2 ? .orange : .accentColor)
        }
        .frame(width: 32, height: 32)
    }

    // MARK: - Features

    private var featuresGrid: some View {
        ProFeatureListView(accentColor: .accentColor)
    }

    // MARK: - Plan Row

    private func planRow(product: ProPlanProduct) -> some View {
        let isSelected = selectedPlan == product.plan

        return Button {
            guard product.isAvailable, !isBusy else {
                return
            }

            withAnimation(.easeInOut(duration: 0.15)) {
                selectedPlan = product.plan
            }
        } label: {
            HStack(spacing: DS.Spacing.md) {
                ZStack {
                    Circle()
                        .stroke(
                            isSelected ? Color.accentColor : Color(nsColor: .separatorColor),
                            lineWidth: isSelected ? 5.5 : 1.5
                        )
                        .frame(width: 18, height: 18)
                    if isSelected {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 7, height: 7)
                    }
                }

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(product.title)
                            .font(DS.Typography.bodyMedium)
                        if let badge = product.badge {
                            Text(badge)
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, DS.Spacing.xxs)
                                .background(
                                    Capsule().fill(
                                        LinearGradient(
                                            colors: [.orange, .pink],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                )
                        }
                        if !product.isAvailable {
                            Text("Unavailable")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(.secondary)
                        }
                    }
                    Text(product.subtitle)
                        .font(DS.Typography.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.xxs) {
                    Text(product.displayPrice)
                        .font(DS.Typography.headlineSmall)
                    Text(product.billingDetail)
                        .font(DS.Typography.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 14)
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

    // MARK: - Helpers

    private var ctaText: String {
        guard selectedProduct.isAvailable else {
            return "Currently Unavailable"
        }

        switch selectedPlan {
        case .yearly:
            return "Subscribe - \(selectedProduct.displayPrice)/year"
        case .lifetime:
            return "Buy Once - \(selectedProduct.displayPrice)"
        }
    }

    private var ctaGradientColors: [Color] {
        selectedProduct.isAvailable
            ? [Color.accentColor, Color.accentColor.opacity(0.8)]
            : [Color.secondary.opacity(0.7), Color.secondary.opacity(0.5)]
    }

    private var cardBorder: Color {
        isExpired ? DS.Colors.warningBorder : DS.Colors.cardBorder
    }

    private func syncSelectedPlan() {
        if proStatusManager.planProduct(for: selectedPlan).isAvailable {
            return
        }

        if let firstAvailablePlan = proStatusManager.availablePlans.first(where: { $0.isAvailable })?.plan {
            selectedPlan = firstAvailablePlan
        }
    }

    private func purchaseSelectedPlan() async {
        guard selectedProduct.isAvailable else {
            return
        }

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

    var body: some View {
        if case .pro(let plan, _, _) = proStatusManager.status {
            VStack(spacing: 0) {
                HStack(alignment: .center, spacing: 14) {
                    DSIconBadge(
                        systemName: "checkmark.seal.fill",
                        iconColor: .green,
                        backgroundColor: DS.Colors.proTint
                    )

                    VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                        HStack(alignment: .center, spacing: DS.Spacing.sm) {
                            Text("Pro")
                                .font(DS.Typography.headlineMedium)

                            Text(plan == .lifetime ? "Lifetime" : "Yearly")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, DS.Spacing.sm)
                                .padding(.vertical, 3)
                                .background(
                                    Capsule().fill(plan == .lifetime ? DS.Colors.proFill : Color.accentColor.opacity(0.9))
                                )
                        }

                VStack(alignment: .leading, spacing: 6) {
                    if let originalPurchaseDate = proStatusManager.currentEntitlementSnapshot?.originalPurchaseDate {
                        metadataRow(label: "Member since", value: formattedDate(originalPurchaseDate))
                        metadataRow(label: "Supporting for", value: "\(supportingDays(since: originalPurchaseDate)) day\(supportingDays(since: originalPurchaseDate) == 1 ? "" : "s")")
                    }

                    if let renewalState = proStatusManager.status.renewalState {
                        metadataRow(label: renewalLabel(for: renewalState), value: renewalDate(for: renewalState))
                        metadataRow(label: "Remaining", value: renewalFooter(for: renewalState))
                    }
                }
                .padding(.top, DS.Spacing.xxs)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, DS.Spacing.xl)
                .padding(.top, 22)
                .padding(.bottom, 18)

                Divider()
                    .padding(.horizontal, DS.Spacing.lg)

                ProFeatureListView(accentColor: .green)
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
                    .padding(.vertical, DS.Spacing.lg)
                }
            }
            .dsCard()
        }
    }

    private func renewalFooter(for renewalState: ProRenewalState) -> String {
        let daysRemaining: Int

        switch renewalState {
        case .renews(_, let remaining), .ends(_, let remaining):
            daysRemaining = remaining
        }

        return "\(daysRemaining) day\(daysRemaining == 1 ? "" : "s") left in current period"
    }

    private func renewalLabel(for renewalState: ProRenewalState) -> String {
        switch renewalState {
        case .renews:
            return "Renews"
        case .ends:
            return "Ends"
        }
    }

    private func renewalDate(for renewalState: ProRenewalState) -> String {
        switch renewalState {
        case .renews(let expirationDate, _), .ends(let expirationDate, _):
            return formattedDate(expirationDate)
        }
    }

    private func formattedDate(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day().year())
    }

    private func metadataRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
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

    private func supportingDays(since date: Date) -> Int {
        let days = Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0
        return max(1, days)
    }

    private func openManageSubscription() {
        guard let url = URL(string: AppStoreLinks.manageSubscriptionsURL) else {
            return
        }

        NSWorkspace.shared.open(url)
    }
}

private struct ProFeatureListView: View {
    let accentColor: Color

    var body: some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), alignment: .leading),
            GridItem(.flexible(), alignment: .leading),
        ], spacing: 10) {
            ForEach(proFeatureItems, id: \.1) { icon, text in
                HStack(spacing: DS.Spacing.sm) {
                    ZStack {
                        Circle()
                            .fill(accentColor.opacity(0.1))
                            .frame(width: 22, height: 22)
                        Image(systemName: icon)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(accentColor)
                    }
                    Text(text)
                        .font(.system(size: 12))
                        .foregroundColor(.primary.opacity(0.8))
                }
            }
        }
    }
}

private struct ProLetterView: View {
    @EnvironmentObject private var proStatusManager: ProStatusManager

    private var isPurchased: Bool {
        proStatusManager.status.isPro
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            Text(isPurchased ? "A Note From Chen" : "Before You Decide")
                .font(DS.Typography.letterLabel)
                .foregroundColor(Color.accentColor.opacity(0.6))

            Text(headline)
                .font(DS.Typography.letterHeadline)
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Text(bodyText)
                .font(DS.Typography.letterBody)
                .foregroundColor(.primary.opacity(0.85))
                .lineSpacing(DS.Spacing.xs)
                .fixedSize(horizontal: false, vertical: true)

            Text(signature)
                .font(DS.Typography.letterSignature)
                .foregroundColor(.primary.opacity(0.7))
                .padding(.top, DS.Spacing.xs)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DS.Spacing.xs)
    }

    private var headline: String {
        isPurchased ? "Thank you for keeping this app small, focused, and cared for." : "Command Reopen is a tiny utility, and we want to keep it that way."
    }

    private var bodyText: String {
        if isPurchased {
            return """
            We built Command Reopen to solve one specific annoyance: when you switch back to an app, the window should actually be there.

            Your support helps us keep the app fast, quiet, and well maintained instead of bloating it with distractions. If it has earned a place in your menu bar, that means a lot.
            """
        }

        return """
        We built Command Reopen to solve one specific annoyance: when you switch back to an app, the window should actually be there.

        Pro keeps the app sustainable without turning it into a noisy product. If the app has been useful, choosing a plan is the most direct way to help us keep improving it.
        """
    }

    private var signature: String {
        isPurchased ? "With thanks,\nChen" : "Warmly,\nChen"
    }
}

// MARK: - Combined Pro Section

struct ProSectionView: View {
    @EnvironmentObject private var proStatusManager: ProStatusManager

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            if proStatusManager.status.isPro {
                ProStatusBadgeView()
            } else {
                UpgradeCardView()
            }

            ProLetterView()
        }
    }
}
