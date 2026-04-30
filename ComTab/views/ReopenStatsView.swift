//
//  ReopenStatsView.swift
//  ComTab
//
//  Created by CHEN on 2026/3/28.
//

import SwiftUI
#if canImport(Charts)
import Charts
#endif

enum StatTimeRange: CaseIterable {
    case day
    case week
    case month

    var title: String {
        switch self {
        case .day:
            return String(localized: "Day")
        case .week:
            return String(localized: "Week")
        case .month:
            return String(localized: "Month")
        }
    }
}

struct ReopenStatsView: View {
    @EnvironmentObject private var reopenStatsStore: ReopenStatsStore

    @State private var timeRange: StatTimeRange = .day
    @State private var showResetConfirmation = false

    private var trendData: [(date: Date, count: Int)] {
        switch timeRange {
        case .day:
            return reopenStatsStore.dailyStats(last: 30)
        case .week:
            return reopenStatsStore.weeklyStats(last: 12)
        case .month:
            return reopenStatsStore.monthlyStats(last: 12)
        }
    }

    private var trendMaxCount: Int {
        trendData.map(\.count).max() ?? 1
    }

    private var activeDaysInLast30: Int {
        reopenStatsStore.dailyStats(last: 30).filter { $0.count > 0 }.count
    }

    var body: some View {
        ScrollView {
            VStack(spacing: DS.Spacing.md) {
                heroSection
                trendSection
                topAppsSection
                resetSection
            }
            .padding(DS.Spacing.md)
        }
        .background(statsBackground)
    }

    private var statsBackground: some View {
        Color(nsColor: .controlBackgroundColor).opacity(0.22)
    }

    private var heroSection: some View {
        HStack(alignment: .center, spacing: DS.Spacing.lg) {
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text("\(reopenStatsStore.totalSuccessfulReopens)")
                    .font(DS.Typography.displayLarge)
                    .foregroundStyle(.primary)
                    .monospacedDigit()
                Text("total reopens")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: DS.Spacing.md)

            HStack(spacing: DS.Spacing.sm) {
                metricTile(
                    title: "Today",
                    value: "\(reopenStatsStore.todayCount)",
                    systemImage: "sun.max.fill",
                    tint: .orange
                )
                metricTile(
                    title: "Active",
                    value: "\(activeDaysInLast30)d",
                    systemImage: "calendar",
                    tint: .teal
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DS.Spacing.md)
        .statsPanel(tint: .accentColor.opacity(0.07))
    }

    private func metricTile(title: String, value: String, systemImage: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)

            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
                Text(title)
                    .font(DS.Typography.microSemibold)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(minWidth: 58, alignment: .leading)
        .padding(.horizontal, DS.Spacing.sm)
        .padding(.vertical, DS.Spacing.xs)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: DS.Radius.smMd, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.smMd, style: .continuous)
                .strokeBorder(tint.opacity(0.18), lineWidth: 1)
        )
    }

    private var trendSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack {
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text("Trend")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(timeRangeSubtitle)
                        .font(DS.Typography.micro)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Picker("", selection: $timeRange) {
                    ForEach(StatTimeRange.allCases, id: \.self) { range in
                        Text(range.title).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 132)
            }

            let allZero = trendData.allSatisfy { $0.count == 0 }

            ZStack {
#if canImport(Charts)
                ChartsTrendView(data: trendData, timeRange: timeRange)
                    .frame(height: 112)
#else
                FallbackTrendView(data: trendData, maxCount: trendMaxCount, timeRange: timeRange)
                    .frame(height: 112)
#endif

                if allZero {
                    emptyState(systemImage: "chart.bar", text: "Start using Command Reopen to see trends")
                }
            }
        }
        .padding(DS.Spacing.md)
        .statsPanel(tint: .blue.opacity(0.04))
    }

    private var topAppsSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text("Top Apps")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                Text("Most often reopened")
                    .font(DS.Typography.micro)
                    .foregroundStyle(.secondary)
            }

            let topApps = reopenStatsStore.topApps(5)
            if topApps.isEmpty {
                emptyState(systemImage: "app.dashed", text: "No reopen activity yet")
                    .frame(height: 58)
            } else {
#if canImport(Charts)
                ChartsTopAppsView(apps: topApps)
                    .frame(height: CGFloat(topApps.count) * 26 + 6)
#else
                FallbackTopAppsView(apps: topApps, maxCount: reopenStatsStore.maxAppCount)
#endif
            }
        }
        .padding(DS.Spacing.md)
        .statsPanel(tint: .teal.opacity(0.04))
    }

    private var resetSection: some View {
        HStack {
            Spacer()
            Button("Reset Statistics", role: .destructive) {
                showResetConfirmation = true
            }
            .font(DS.Typography.caption)
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(reopenStatsStore.totalSuccessfulReopens == 0)
            .alert("Reset Statistics?", isPresented: $showResetConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Reset", role: .destructive) {
                    reopenStatsStore.reset()
                }
            } message: {
                Text("Are you sure? This cannot be undone.")
            }
            Spacer()
        }
        .padding(.top, DS.Spacing.xs)
    }

    private func emptyState(systemImage: String, text: String) -> some View {
        VStack(spacing: DS.Spacing.xs) {
            Image(systemName: systemImage)
                .font(.system(size: 18))
                .foregroundStyle(.secondary.opacity(0.48))
            Text(text)
                .font(DS.Typography.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: DS.Radius.smMd, style: .continuous))
    }

    private var timeRangeSubtitle: String {
        switch timeRange {
        case .day:
            return "Last 30 days"
        case .week:
            return "Last 12 weeks"
        case .month:
            return "Last 12 months"
        }
    }
}

#if canImport(Charts)
private struct ChartsTrendView: View {
    let data: [(date: Date, count: Int)]
    let timeRange: StatTimeRange

    var body: some View {
        Chart {
            ForEach(Array(data.enumerated()), id: \.offset) { _, item in
                BarMark(
                    x: .value("Date", item.date, unit: calendarUnit),
                    y: .value("Count", item.count)
                )
                .foregroundStyle(item.count > 0 ? Color.accentColor : Color.secondary.opacity(0.18))
                .cornerRadius(3)
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.3))
                AxisValueLabel(format: xAxisFormat)
                    .font(.system(size: 9))
            }
        }
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.3))
                AxisValueLabel()
                    .font(.system(size: 9))
            }
        }
    }

    private var calendarUnit: Calendar.Component {
        switch timeRange {
        case .day:
            return .day
        case .week:
            return .weekOfYear
        case .month:
            return .month
        }
    }

    private var xAxisFormat: Date.FormatStyle {
        switch timeRange {
        case .day:
            return .dateTime.month(.abbreviated).day()
        case .week:
            return .dateTime.month(.abbreviated).day()
        case .month:
            return .dateTime.month(.abbreviated)
        }
    }
}

private struct ChartsTopAppsView: View {
    let apps: [ReopenStatsStore.AppStat]

    var body: some View {
        Chart {
            ForEach(Array(apps.enumerated()), id: \.element.id) { index, app in
                BarMark(
                    x: .value("Count", app.count),
                    y: .value("App", app.displayName)
                )
                .foregroundStyle(topAppColor(at: index))
                .cornerRadius(4)
                .annotation(position: .trailing, alignment: .leading, spacing: 4) {
                    Text("\(app.count)")
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .chartYAxis {
            AxisMarks { _ in
                AxisValueLabel()
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .chartXAxis(.hidden)
    }

    private func topAppColor(at index: Int) -> Color {
        switch index {
        case 0:
            return .accentColor
        case 1:
            return .blue.opacity(0.82)
        case 2:
            return .teal.opacity(0.78)
        default:
            return .secondary.opacity(0.55)
        }
    }
}
#endif

private struct FallbackTrendView: View {
    let data: [(date: Date, count: Int)]
    let maxCount: Int
    let timeRange: StatTimeRange

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(Array(data.enumerated()), id: \.offset) { _, item in
                VStack(spacing: 4) {
                    Spacer(minLength: 0)
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color.accentColor.opacity(item.count > 0 ? 1 : 0.15))
                        .frame(height: barHeight(for: item.count))
                }
            }
        }
        .padding(.bottom, 20)
        .overlay(alignment: .bottom) {
            xAxisLabels
        }
    }

    private func barHeight(for count: Int) -> CGFloat {
        guard maxCount > 0 else { return 3 }
        return max(3, CGFloat(count) / CGFloat(maxCount) * 110)
    }

    private var xAxisLabels: some View {
        HStack {
            if let first = data.first {
                Text(formatLabel(first.date))
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
            Spacer()
            if let last = data.last {
                Text(formatLabel(last.date))
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
        }
    }

    private func formatLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        switch timeRange {
        case .day, .week:
            formatter.dateFormat = "MMM d"
        case .month:
            formatter.dateFormat = "MMM"
        }
        return formatter.string(from: date)
    }
}

private struct FallbackTopAppsView: View {
    let apps: [ReopenStatsStore.AppStat]
    let maxCount: Int

    var body: some View {
        VStack(spacing: DS.Spacing.sm) {
            ForEach(Array(apps.enumerated()), id: \.element.id) { index, app in
                HStack(spacing: DS.Spacing.sm) {
                    Text("\(index + 1)")
                        .font(DS.Typography.microSemibold)
                        .foregroundColor(fallbackTopAppColor(at: index))
                        .frame(width: 14, alignment: .leading)

                    Text(app.displayName)
                        .font(.system(size: 11))
                        .frame(width: 78, alignment: .leading)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    GeometryReader { geometry in
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(fallbackTopAppColor(at: index))
                            .frame(width: barWidth(for: app.count, in: geometry.size.width))
                    }
                    .frame(height: 18)

                    Text("\(app.count)")
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                        .frame(width: 28, alignment: .leading)
                }
                .frame(height: 20)
            }
        }
    }

    private func barWidth(for count: Int, in totalWidth: CGFloat) -> CGFloat {
        guard maxCount > 0 else { return 4 }
        return max(4, CGFloat(count) / CGFloat(maxCount) * totalWidth)
    }

    private func fallbackTopAppColor(at index: Int) -> Color {
        switch index {
        case 0:
            return .accentColor
        case 1:
            return .blue.opacity(0.82)
        case 2:
            return .teal.opacity(0.78)
        default:
            return .secondary.opacity(0.55)
        }
    }
}

private extension View {
    func statsPanel(tint: Color) -> some View {
        self
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: DS.Radius.smMd, style: .continuous))
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.smMd, style: .continuous)
                    .fill(tint)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.smMd, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
    }
}
