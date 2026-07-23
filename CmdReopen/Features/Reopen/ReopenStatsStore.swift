//
//  ReopenStatsStore.swift
//  CmdReopen
//
//  Created by CHEN on 2026/3/28.
//

import Combine
import Foundation
import StoreKit

protocol AppReviewPrompting {
    @MainActor
    func requestReview()
}

enum ReviewPromptTrigger: Equatable {
    /// A purchase is a high-confidence moment of customer satisfaction and
    /// does not require a reopen-count threshold.
    case purchaseCompleted
    case statsOpened
    case launchAtLoginEnabled
    case applicationLaunched

    fileprivate var requiresReopenHistory: Bool {
        self != .purchaseCompleted
    }
}

struct StoreKitAppReviewPrompter: AppReviewPrompting {
    func requestReview() {
        SKStoreReviewController.requestReview()
    }
}

@MainActor
final class ReopenStatsStore: ObservableObject {
    struct Snapshot: Equatable, Codable {
        var totalSuccessfulReopens: Int
        var perAppCounts: [String: Int]
        var perAppDisplayName: [String: String]
        var dailyCounts: [String: Int]
        var dailyAppCounts: [String: [String: Int]]?
        var lastUpdatedAt: Date?

        static let empty = Snapshot(
            totalSuccessfulReopens: 0,
            perAppCounts: [:],
            perAppDisplayName: [:],
            dailyCounts: [:],
            dailyAppCounts: nil,
            lastUpdatedAt: nil
        )
    }

    struct AppStat: Identifiable, Equatable {
        let bundleID: String
        let displayName: String
        let count: Int

        var id: String { bundleID }
    }

    private struct LegacySnapshot: Codable {
        var totalSuccessfulReopens: Int
        var perAppCounts: [String: Int]
        var perAppDisplayName: [String: String]
        var lastUpdatedAt: Date?
    }

    private enum ReviewPrompt {
        static let minimumSuccessfulReopens = 20
        static let maximumRequestsPerYear = 3
        static let rollingWindow: TimeInterval = 365 * 24 * 60 * 60
        static let requestTimestampsKey = "cmdreopenReviewPromptRequestTimestamps"
        static let migratedHistoryKey = "cmdreopenReviewPromptMigratedHistory"

        // Previous builds stored milestones rather than dates. Retain these
        // keys only to migrate their request count into the rolling cap.
        static let promptedMilestonesKey = "cmdreopenReviewPromptedReopenMilestones"
        static let legacyPromptedMilestonesKey = "comtabReviewPromptedReopenMilestones"
    }

    private enum LegacyStorageKey {
        static let reopenStats = "com.comtab.reopenStats"
    }

    static let shared = ReopenStatsStore()

    static let dayKeyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    @Published private(set) var snapshot: Snapshot

    private let defaults: UserDefaults
    private let storageKey: String
    private let distributionChannel: DistributionChannel
    private let appReviewPrompter: any AppReviewPrompting
    private let encoder = JSONEncoder()
    private var hasRequestedReviewThisLaunch = false

    var totalSuccessfulReopens: Int {
        snapshot.totalSuccessfulReopens
    }

    var todayCount: Int {
        let key = Self.dayKeyFormatter.string(from: Date())
        return snapshot.dailyCounts[key] ?? 0
    }

    var appStats: [AppStat] {
        snapshot.perAppCounts.map { bundleID, count in
            AppStat(
                bundleID: bundleID,
                displayName: snapshot.perAppDisplayName[bundleID] ?? bundleID,
                count: count
            )
        }
        .sorted { lhs, rhs in
            if lhs.count != rhs.count {
                return lhs.count > rhs.count
            }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }

    func topApps(_ count: Int = 6) -> [AppStat] {
        Array(appStats.prefix(count))
    }

    func topApps(_ count: Int = 5, since startDate: Date) -> [AppStat] {
        let startKey = Self.dayKeyFormatter.string(from: startDate)
        let dailyAppCounts = snapshot.dailyAppCounts ?? [:]
        var filtered: [String: Int] = [:]
        for (dayKey, appCounts) in dailyAppCounts where dayKey >= startKey {
            for (bundleID, count) in appCounts {
                filtered[bundleID, default: 0] += count
            }
        }
        return filtered.map { bundleID, count in
            AppStat(
                bundleID: bundleID,
                displayName: snapshot.perAppDisplayName[bundleID] ?? bundleID,
                count: count
            )
        }
        .sorted { lhs, rhs in
            if lhs.count != rhs.count { return lhs.count > rhs.count }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
        .prefix(count)
        .map { $0 }
    }

    var maxAppCount: Int {
        snapshot.perAppCounts.values.max() ?? 0
    }

    func dailyStats(last days: Int = 30) -> [(date: Date, count: Int)] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<days).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else {
                return nil
            }
            let key = Self.dayKeyFormatter.string(from: date)
            return (date: date, count: snapshot.dailyCounts[key] ?? 0)
        }
    }

    func weeklyStats(last weeks: Int = 12) -> [(date: Date, count: Int)] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<weeks).reversed().compactMap { offset in
            guard let weekStart = calendar.date(byAdding: .weekOfYear, value: -offset, to: today) else {
                return nil
            }
            guard let firstDayOfWeek = calendar.date(
                from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: weekStart)
            ) else {
                return nil
            }

            var total = 0
            for dayOffset in 0..<7 {
                guard let day = calendar.date(byAdding: .day, value: dayOffset, to: firstDayOfWeek) else {
                    continue
                }
                let key = Self.dayKeyFormatter.string(from: day)
                total += snapshot.dailyCounts[key] ?? 0
            }
            return (date: firstDayOfWeek, count: total)
        }
    }

    func monthlyStats(last months: Int = 12) -> [(date: Date, count: Int)] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<months).reversed().compactMap { offset in
            guard let monthStart = calendar.date(byAdding: .month, value: -offset, to: today) else {
                return nil
            }
            guard let firstOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: monthStart)) else {
                return nil
            }
            guard let range = calendar.range(of: .day, in: .month, for: firstOfMonth) else {
                return nil
            }

            var total = 0
            for dayIndex in range {
                guard let day = calendar.date(byAdding: .day, value: dayIndex - 1, to: firstOfMonth) else {
                    continue
                }
                let key = Self.dayKeyFormatter.string(from: day)
                total += snapshot.dailyCounts[key] ?? 0
            }
            return (date: firstOfMonth, count: total)
        }
    }

    init(
        defaults: UserDefaults = .standard,
        storageKey: String = "com.cmdreopen.reopenStats",
        distributionChannel: DistributionChannel = .current,
        appReviewPrompter: (any AppReviewPrompting)? = nil
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
        self.distributionChannel = distributionChannel
        self.appReviewPrompter = appReviewPrompter ?? StoreKitAppReviewPrompter()
        let loaded = Self.loadSnapshot(defaults: defaults, storageKey: storageKey)
            ?? Self.migrateSnapshot(defaults: defaults, from: LegacyStorageKey.reopenStats, to: storageKey)
            ?? .empty
        let sanitized = Self.removingHelperEntries(from: loaded)
        self.snapshot = sanitized
        if sanitized != loaded {
            persist(sanitized)
        }
        Self.migrateArray(
            defaults: defaults,
            from: ReviewPrompt.legacyPromptedMilestonesKey,
            to: ReviewPrompt.promptedMilestonesKey
        )
        Self.migrateReviewPromptHistoryIfNeeded(defaults: defaults)
    }

    func recordSuccessfulReopen(bundleID: String, localizedName: String?, bundleURL: URL? = nil) {
        guard let normalizedBundleID = Self.normalize(bundleID) else {
            return
        }
        guard !HelperProcessFilter.isHelperLike(
            bundleID: normalizedBundleID,
            bundleURL: bundleURL,
            localizedName: localizedName
        ) else {
            return
        }

        var next = snapshot
        next.totalSuccessfulReopens += 1
        next.perAppCounts[normalizedBundleID, default: 0] += 1
        if let localizedName = Self.normalize(localizedName) {
            next.perAppDisplayName[normalizedBundleID] = localizedName
        }
        let dayKey = Self.dayKeyFormatter.string(from: Date())
        next.dailyCounts[dayKey, default: 0] += 1
        if next.dailyAppCounts == nil { next.dailyAppCounts = [:] }
        next.dailyAppCounts![dayKey, default: [:]][normalizedBundleID, default: 0] += 1
        next.lastUpdatedAt = Date()

        persist(next)
    }

    /// Requests an App Store review only at an intentional product moment.
    /// StoreKit may still decide not to show the system dialog.
    @discardableResult
    func requestReviewIfEligible(
        for trigger: ReviewPromptTrigger,
        now: Date = Date()
    ) -> Bool {
        guard distributionChannel == .appStore,
              !hasRequestedReviewThisLaunch else {
            return false
        }

        if trigger.requiresReopenHistory,
           totalSuccessfulReopens <= ReviewPrompt.minimumSuccessfulReopens {
            return false
        }

        let cutoff = now.addingTimeInterval(-ReviewPrompt.rollingWindow).timeIntervalSince1970
        var requestTimestamps = (defaults.array(forKey: ReviewPrompt.requestTimestampsKey) as? [Double] ?? [])
            .filter { $0 > cutoff }

        guard requestTimestamps.count < ReviewPrompt.maximumRequestsPerYear else {
            defaults.set(requestTimestamps, forKey: ReviewPrompt.requestTimestampsKey)
            return false
        }

        requestTimestamps.append(now.timeIntervalSince1970)
        defaults.set(requestTimestamps, forKey: ReviewPrompt.requestTimestampsKey)
        hasRequestedReviewThisLaunch = true
        appReviewPrompter.requestReview()
        return true
    }

    func reset() {
        snapshot = .empty
        defaults.removeObject(forKey: storageKey)
    }

    private func persist(_ snapshot: Snapshot) {
        self.snapshot = snapshot

        guard let data = try? encoder.encode(snapshot) else {
            return
        }
        defaults.set(data, forKey: storageKey)
    }

    /// One-time subtractive cleanup for snapshots recorded before helper
    /// processes were excluded: removes helper entries and subtracts their
    /// counts so historical totals stay consistent. Days that only exist in
    /// `dailyCounts` (no per-app breakdown) are left untouched because the
    /// helper share cannot be attributed.
    private static func removingHelperEntries(from snapshot: Snapshot) -> Snapshot {
        let helperBundleIDs = snapshot.perAppCounts.keys.filter { bundleID in
            HelperProcessFilter.isHelperLike(
                bundleID: bundleID,
                bundleURL: nil,
                localizedName: snapshot.perAppDisplayName[bundleID]
            )
        }
        guard !helperBundleIDs.isEmpty else { return snapshot }

        var next = snapshot
        var removedTotal = 0
        for bundleID in helperBundleIDs {
            removedTotal += next.perAppCounts[bundleID] ?? 0
            next.perAppCounts.removeValue(forKey: bundleID)
            next.perAppDisplayName.removeValue(forKey: bundleID)
        }
        next.totalSuccessfulReopens = max(0, next.totalSuccessfulReopens - removedTotal)

        if var dailyAppCounts = next.dailyAppCounts {
            for (dayKey, counts) in dailyAppCounts {
                var counts = counts
                var removedInDay = 0
                for bundleID in helperBundleIDs {
                    removedInDay += counts[bundleID] ?? 0
                    counts.removeValue(forKey: bundleID)
                }
                dailyAppCounts[dayKey] = counts
                if removedInDay > 0 {
                    next.dailyCounts[dayKey] = max(0, (next.dailyCounts[dayKey] ?? 0) - removedInDay)
                }
            }
            next.dailyAppCounts = dailyAppCounts
        }
        return next
    }

    private static func loadSnapshot(defaults: UserDefaults, storageKey: String) -> Snapshot? {
        guard let data = defaults.data(forKey: storageKey) else {
            return nil
        }

        if let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) {
            return snapshot
        }

        guard let legacySnapshot = try? JSONDecoder().decode(LegacySnapshot.self, from: data) else {
            return nil
        }

        return Snapshot(
            totalSuccessfulReopens: legacySnapshot.totalSuccessfulReopens,
            perAppCounts: legacySnapshot.perAppCounts,
            perAppDisplayName: legacySnapshot.perAppDisplayName,
            dailyCounts: [:],
            dailyAppCounts: nil,
            lastUpdatedAt: legacySnapshot.lastUpdatedAt
        )
    }

    private static func migrateSnapshot(defaults: UserDefaults, from legacyKey: String, to currentKey: String) -> Snapshot? {
        guard defaults.object(forKey: currentKey) == nil,
              let snapshot = loadSnapshot(defaults: defaults, storageKey: legacyKey) else {
            return nil
        }

        if let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: currentKey)
            defaults.removeObject(forKey: legacyKey)
        }
        return snapshot
    }

    private static func migrateArray(defaults: UserDefaults, from legacyKey: String, to currentKey: String) {
        guard defaults.object(forKey: currentKey) == nil,
              let legacyValue = defaults.array(forKey: legacyKey) else {
            return
        }

        defaults.set(legacyValue, forKey: currentKey)
        defaults.removeObject(forKey: legacyKey)
    }

    private static func migrateReviewPromptHistoryIfNeeded(defaults: UserDefaults) {
        guard !defaults.bool(forKey: ReviewPrompt.migratedHistoryKey) else {
            return
        }

        defer { defaults.set(true, forKey: ReviewPrompt.migratedHistoryKey) }

        guard defaults.object(forKey: ReviewPrompt.requestTimestampsKey) == nil else {
            return
        }

        let legacyRequestCount = min(
            ReviewPrompt.maximumRequestsPerYear,
            (defaults.array(forKey: ReviewPrompt.promptedMilestonesKey) as? [Int] ?? []).count
        )
        guard legacyRequestCount > 0 else {
            return
        }

        // The former implementation did not record dates. Treat its known
        // requests conservatively so this release cannot immediately exceed
        // Apple's rolling annual limit after upgrading.
        let timestamp = Date().timeIntervalSince1970
        defaults.set(
            Array(repeating: timestamp, count: legacyRequestCount),
            forKey: ReviewPrompt.requestTimestampsKey
        )
    }

    private static func normalize(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
