//
//  DesignCatalog.swift
//  ComTab
//
//  DEBUG-only component catalog — open the preview to review all design tokens
//  and components side-by-side in Light / Dark mode.
//
#if DEBUG
import SwiftUI

struct DesignCatalog: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                catalogSection("Status Pills") { pillRow }
                catalogSection("Metric Tiles") { tileRow }
                catalogSection("Icon Badges") { badgeRow }
                catalogSection("Section Headers") { headerRow }
                catalogSection("Empty States") { emptyStateRow }
                catalogSection("Cards (dsCard)") { cardRow }
            }
            .padding(40)
        }
        .frame(width: 720)
    }

    // MARK: - Rows

    private var pillRow: some View {
        HStack(spacing: 12) {
            StatusPill(text: "Best Value", tone: .accent)
            StatusPill(text: "Warning", tone: .warning)
            StatusPill(text: "Unavailable", tone: .neutral)
            StatusPill(text: "Lifetime", tone: .accent)
            StatusPill(text: "Yearly", tone: .accent)
        }
    }

    private var tileRow: some View {
        HStack(spacing: 12) {
            MetricTile(title: "Today", value: "12", systemImage: "sun.max.fill", tint: .orange)
            MetricTile(title: "Active", value: "28d", systemImage: "calendar", tint: .teal)
            MetricTile(title: "Total", value: "519", systemImage: "arrow.clockwise", tint: .accentColor)
        }
    }

    private var badgeRow: some View {
        HStack(spacing: 16) {
            DSIconBadge(systemName: "checkmark.seal.fill", iconColor: .accentColor, backgroundColor: DS.Colors.accentTint)
            DSIconBadge(systemName: "exclamationmark.triangle.fill", iconColor: .orange, backgroundColor: DS.Colors.warningTint)
            DSIconBadge(systemName: "chart.bar.xaxis", iconColor: .accentColor, backgroundColor: DS.Colors.accentTint, size: 36, iconSize: 15)
        }
    }

    private var headerRow: some View {
        VStack(spacing: 12) {
            SectionHeader(title: "Trend", subtitle: "Last 30 days") {
                Text("Picker placeholder")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Divider()
            SectionHeader(title: "Top Apps", subtitle: "Most often reopened")
        }
    }

    private var emptyStateRow: some View {
        HStack(spacing: 16) {
            EmptyStateView(systemImage: "chart.bar", text: "Start using Command Reopen to see trends")
                .frame(height: 80)
            EmptyStateView(systemImage: "app.dashed", text: "No reopen activity yet")
                .frame(height: 80)
        }
    }

    private var cardRow: some View {
        VStack(spacing: 12) {
            Text("Card content example")
                .padding()
                .frame(maxWidth: .infinity)
                .dsCard()

            Text("Warning-tinted card")
                .padding()
                .frame(maxWidth: .infinity)
                .dsCard(borderColor: DS.Colors.warningTint)
        }
    }

    // MARK: - Helper

    private func catalogSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)
            content()
        }
    }
}

#Preview("Design Catalog") {
    DesignCatalog()
}
#endif
