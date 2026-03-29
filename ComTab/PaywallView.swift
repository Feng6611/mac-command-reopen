//
//  PaywallView.swift
//  ComTab
//
//  Created by CHEN on 2026/3/28.
//

import AppKit
import SwiftUI
import os

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
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 20)

            featuresGrid
                .padding(.horizontal, 20)
                .padding(.bottom, 24)

            Divider()
                .padding(.horizontal, 16)

            Group {
                if isLoadingOfferings {
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                } else {
                    VStack(spacing: 12) {
                        ForEach(proStatusManager.availablePlans) { product in
                            planRow(product: product)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 18)

            if let paywallErrorMessage = proStatusManager.paywallErrorMessage {
                Text(paywallErrorMessage)
                    .font(.system(size: 11))
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
            }

            Button {
                Task {
                    await purchaseSelectedPlan()
                }
            } label: {
                HStack(spacing: 8) {
                    if isPurchasingSelectedPlan {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                    } else {
                        Image(systemName: "lock.open.fill")
                            .font(.system(size: 12))
                    }

                    Text(ctaText)
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
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
            .padding(.horizontal, 16)
            .padding(.bottom, 16)

            HStack(spacing: 10) {
                Button(proStatusManager.isRestoringPurchases ? "Restoring..." : "Restore Purchase") {
                    Task {
                        await restorePurchases()
                    }
                }
                .buttonStyle(.link)
                .font(.system(size: 11))
                .disabled(isBusy)

                Circle()
                    .fill(Color.secondary.opacity(0.4))
                    .frame(width: 3, height: 3)

                Button("Terms") {
                    openExternalURL(ExternalLinks.officialURL)
                }
                .buttonStyle(.link)
                .font(.system(size: 11))

                Circle()
                    .fill(Color.secondary.opacity(0.4))
                    .frame(width: 3, height: 3)

                Button("Privacy") {
                    openExternalURL(ExternalLinks.officialURL)
                }
                .buttonStyle(.link)
                .font(.system(size: 11))
            }
            .padding(.bottom, 20)
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(cardBorder, lineWidth: 1)
        )
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
            ZStack {
                Circle()
                    .fill(isExpired ? Color.orange.opacity(0.15) : Color.accentColor.opacity(0.12))
                    .frame(width: 36, height: 36)
                Image(systemName: isExpired ? "exclamationmark.triangle.fill" : "clock.fill")
                    .font(.system(size: 16))
                    .foregroundColor(isExpired ? .orange : .accentColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                if isExpired {
                    Text("Trial Expired")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Upgrade to continue using Command Reopen")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                } else if case .trial(let days, _) = proStatusManager.status {
                    Text("Pro Trial")
                        .font(.system(size: 14, weight: .semibold))
                    Text("\(days) day\(days == 1 ? "" : "s") remaining")
                        .font(.system(size: 11))
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
        let features: [(String, String)] = [
            ("arrow.clockwise", "Auto-reopen windows"),
            ("slider.horizontal.3", "Per-app exclusion"),
            ("chart.bar", "Statistics & insights"),
            ("arrow.up.circle", "Future updates"),
        ]

        return LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible()),
        ], alignment: .leading, spacing: 8) {
            ForEach(features, id: \.1) { icon, text in
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.accentColor)
                        .frame(width: 14)
                    Text(text)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
        }
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
            HStack(spacing: 12) {
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
                            .font(.system(size: 13, weight: .medium))
                        if let badge = product.badge {
                            Text(badge)
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
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
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                Spacer()

                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(product.displayPrice)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                    Text(product.billingDetail)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.06) : Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(
                        isSelected ? Color.accentColor.opacity(0.5) : Color(nsColor: .separatorColor).opacity(0.5),
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

    private var cardBackground: Color {
        Color(nsColor: .windowBackgroundColor)
    }

    private var cardBorder: Color {
        isExpired ? Color.orange.opacity(0.3) : Color(nsColor: .separatorColor).opacity(0.5)
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
        if case .pro(let plan, _) = proStatusManager.status {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color.green.opacity(0.12))
                        .frame(width: 36, height: 36)
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.green)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("Pro")
                            .font(.system(size: 14, weight: .semibold))
                        Text(plan == .lifetime ? "Lifetime" : "Yearly")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule().fill(Color.green.opacity(0.8))
                            )
                    }
                    Text("Thank you for your support!")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 1)
            )
        }
    }
}

// MARK: - onChange backward-compatibility shim (macOS 12+)

private struct OnChangeCompat<V: Equatable>: ViewModifier {
    let value: V
    let action: () -> Void

    func body(content: Content) -> some View {
        if #available(macOS 14.0, *) {
            content.onChange(of: value) { action() }
        } else {
            content.onChange(of: value) { _ in action() }
        }
    }
}

// MARK: - Combined Pro Section

struct ProSectionView: View {
    @EnvironmentObject private var proStatusManager: ProStatusManager

    var body: some View {
        Group {
            if proStatusManager.status.isPro {
                ProStatusBadgeView()
            } else {
                UpgradeCardView()
            }
        }
    }
}
