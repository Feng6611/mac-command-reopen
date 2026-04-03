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

    var body: some View {
        ScrollView {
            VStack(spacing: DS.Spacing.lg) {
                heroSection
                trendSection
                topAppsSection
                resetSection
            }
            .padding(DS.Spacing.xl)
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
    }

    private var heroSection: some View {
        VStack(spacing: DS.Spacing.xxs) {
            Text("\(reopenStatsStore.totalSuccessfulReopens)")
                .font(DS.Typography.displayLarge)
                .foregroundStyle(.primary)
            Text("total reopens")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Text("\(reopenStatsStore.todayCount) today")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary.opacity(0.7))
                .padding(.top, DS.Spacing.xs)
        }
        .frame(maxWidth: .infinity)
        .padding(DS.Spacing.lg)
        .dsCard(borderColor: DS.Colors.cardBorderSubtle, radius: DS.Radius.md)
    }

    private var trendSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            HStack {
                Text("Trend")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("", selection: $timeRange) {
                    ForEach(StatTimeRange.allCases, id: \.self) { range in
                        Text(range.title).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 160)
            }

            let allZero = trendData.allSatisfy { $0.count == 0 }

            ZStack {
#if canImport(Charts)
                if #available(macOS 13.0, *) {
                    ChartsTrendView(data: trendData, timeRange: timeRange)
                        .frame(height: 140)
                } else {
                    FallbackTrendView(data: trendData, maxCount: trendMaxCount, timeRange: timeRange)
                        .frame(height: 140)
                }
#else
                FallbackTrendView(data: trendData, maxCount: trendMaxCount, timeRange: timeRange)
                    .frame(height: 140)
#endif

                if allZero {
                    Text("Start using Command Reopen to see trends")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(nsColor: .windowBackgroundColor).opacity(0.6))
                }
            }
        }
        .padding(DS.Spacing.lg)
        .dsCard(borderColor: DS.Colors.cardBorderSubtle, radius: DS.Radius.md)
    }

    private var topAppsSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            Text("Top Apps")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            let topApps = reopenStatsStore.topApps(6)
            if topApps.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 6) {
                        Image(systemName: "app.dashed")
                            .font(.system(size: 20))
                            .foregroundStyle(.secondary.opacity(0.5))
                        Text("No reopen activity yet")
                            .foregroundStyle(.secondary)
                            .font(DS.Typography.caption)
                    }
                    Spacer()
                }
                .padding(.vertical, DS.Spacing.lg)
            } else {
#if canImport(Charts)
                if #available(macOS 13.0, *) {
                    ChartsTopAppsView(apps: topApps)
                        .frame(height: CGFloat(topApps.count) * 30 + 8)
                } else {
                    FallbackTopAppsView(apps: topApps, maxCount: reopenStatsStore.maxAppCount)
                }
#else
                FallbackTopAppsView(apps: topApps, maxCount: reopenStatsStore.maxAppCount)
#endif
            }
        }
        .padding(DS.Spacing.lg)
        .dsCard(borderColor: DS.Colors.cardBorderSubtle, radius: DS.Radius.md)
    }

    private var resetSection: some View {
        HStack {
            Spacer()
            Button("Reset Statistics", role: .destructive) {
                showResetConfirmation = true
            }
            .font(DS.Typography.caption)
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
}

#if canImport(Charts)
@available(macOS 13.0, *)
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
                .foregroundStyle(Color.accentColor.gradient)
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

@available(macOS 13.0, *)
private struct ChartsTopAppsView: View {
    let apps: [ReopenStatsStore.AppStat]

    var body: some View {
        Chart {
            ForEach(Array(apps.enumerated()), id: \.element.id) { index, app in
                BarMark(
                    x: .value("Count", app.count),
                    y: .value("App", app.displayName)
                )
                .foregroundStyle(Color.accentColor.opacity(1.0 - Double(index) * 0.12))
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
                    .font(.system(size: 10))
            }
        }
        .chartXAxis(.hidden)
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
                    Text(app.displayName)
                        .font(.system(size: 11))
                        .frame(width: 80, alignment: .trailing)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    GeometryReader { geometry in
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color.accentColor.opacity(1.0 - Double(index) * 0.12))
                            .frame(width: barWidth(for: app.count, in: geometry.size.width))
                    }
                    .frame(height: 18)

                    Text("\(app.count)")
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                        .frame(width: 28, alignment: .leading)
                }
            }
        }
    }

    private func barWidth(for count: Int, in totalWidth: CGFloat) -> CGFloat {
        guard maxCount > 0 else { return 4 }
        return max(4, CGFloat(count) / CGFloat(maxCount) * totalWidth)
    }
}
