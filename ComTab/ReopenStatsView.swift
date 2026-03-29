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

private struct CardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor).opacity(0.4), lineWidth: 0.5)
            )
    }
}

private extension View {
    func statsCard() -> some View {
        modifier(CardModifier())
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
            VStack(spacing: 16) {
                heroSection
                trendSection
                topAppsSection
                resetSection
            }
            .padding(20)
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
    }

    private var heroSection: some View {
        VStack(spacing: 2) {
            Text("\(reopenStatsStore.totalSuccessfulReopens)")
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
            Text("total reopens")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            Text("\(reopenStatsStore.todayCount) today")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundColor(.secondary.opacity(0.7))
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .statsCard()
    }

    private var trendSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Trend")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
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
                    Text("Start using ComTab to see trends")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(nsColor: .windowBackgroundColor).opacity(0.6))
                }
            }
        }
        .statsCard()
    }

    private var topAppsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Top Apps")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)

            let topApps = reopenStatsStore.topApps(6)
            if topApps.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 6) {
                        Image(systemName: "app.dashed")
                            .font(.system(size: 20))
                            .foregroundColor(.secondary.opacity(0.5))
                        Text("No reopen activity yet")
                            .foregroundColor(.secondary)
                            .font(.system(size: 11))
                    }
                    Spacer()
                }
                .padding(.vertical, 16)
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
        .statsCard()
    }

    private var resetSection: some View {
        HStack {
            Spacer()
            Button("Reset Statistics", role: .destructive) {
                showResetConfirmation = true
            }
            .font(.system(size: 11))
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
        .padding(.top, 4)
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

    private static let barColors: [Color] = [.blue, .purple, .orange, .green, .pink, .teal]

    var body: some View {
        Chart {
            ForEach(Array(apps.enumerated()), id: \.element.id) { index, app in
                BarMark(
                    x: .value("Count", app.count),
                    y: .value("App", app.displayName)
                )
                .foregroundStyle(Self.barColors[index % Self.barColors.count])
                .cornerRadius(4)
                .annotation(position: .trailing, alignment: .leading, spacing: 4) {
                    Text("\(app.count)")
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
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

    private static let barColors: [Color] = [.blue, .purple, .orange, .green, .pink, .teal]

    var body: some View {
        VStack(spacing: 8) {
            ForEach(Array(apps.enumerated()), id: \.element.id) { index, app in
                HStack(spacing: 8) {
                    Text(app.displayName)
                        .font(.system(size: 11))
                        .frame(width: 80, alignment: .trailing)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    GeometryReader { geometry in
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Self.barColors[index % Self.barColors.count])
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
