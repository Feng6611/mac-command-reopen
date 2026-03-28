//
//  ReopenStatsStore.swift
//  ComTab
//
//  Created by CHEN on 2026/3/28.
//

import Combine
import Foundation

@MainActor
final class ReopenStatsStore: ObservableObject {
    struct Snapshot: Codable, Equatable {
        var totalSuccessfulReopens: Int
        var perAppCounts: [String: Int]
        var perAppDisplayName: [String: String]
        var lastUpdatedAt: Date?

        static let empty = Snapshot(
            totalSuccessfulReopens: 0,
            perAppCounts: [:],
            perAppDisplayName: [:],
            lastUpdatedAt: nil
        )
    }

    struct AppStat: Identifiable, Equatable {
        let bundleID: String
        let displayName: String
        let count: Int

        var id: String { bundleID }
    }

    static let shared = ReopenStatsStore()

    private enum Constants {
        static let storageKey = "com.comtab.reopenStats"
    }

    @Published private(set) var snapshot: Snapshot

    private let defaults: UserDefaults
    private let storageKey: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    var totalSuccessfulReopens: Int {
        snapshot.totalSuccessfulReopens
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

    init(defaults: UserDefaults = .standard, storageKey: String = "com.comtab.reopenStats") {
        self.defaults = defaults
        self.storageKey = storageKey
        self.snapshot = Self.loadSnapshot(defaults: defaults, storageKey: storageKey) ?? .empty
    }

    func recordSuccessfulReopen(bundleID: String, localizedName: String?) {
        guard let normalizedBundleID = Self.normalize(bundleID) else {
            return
        }

        var next = snapshot
        next.totalSuccessfulReopens += 1
        next.perAppCounts[normalizedBundleID, default: 0] += 1
        if let localizedName = Self.normalize(localizedName) {
            next.perAppDisplayName[normalizedBundleID] = localizedName
        }
        next.lastUpdatedAt = Date()

        persist(next)
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

    private static func loadSnapshot(defaults: UserDefaults, storageKey: String) -> Snapshot? {
        guard let data = defaults.data(forKey: storageKey) else {
            return nil
        }

        return try? JSONDecoder().decode(Snapshot.self, from: data)
    }

    private static func normalize(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
