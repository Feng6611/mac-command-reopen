//
//  ApplicationLookupProvider.swift
//  CmdReopen
//
//  App metadata lookup and fuzzy matching for the Settings exclude list.
//

import AppKit
import Foundation

struct ExcludedApplicationInfo: Hashable, Identifiable {
    let bundleID: String
    let applicationURL: URL?
    private let resolvedDisplayName: String?

    var id: String { bundleID }

    var displayName: String {
        if let resolvedDisplayName {
            return resolvedDisplayName
        }

        guard let applicationURL else {
            return bundleID
        }

        let bundle = Bundle(url: applicationURL)
        return bundle?.localizedInfoDictionary?["CFBundleDisplayName"] as? String
            ?? bundle?.localizedInfoDictionary?["CFBundleName"] as? String
            ?? bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? FileManager.default.displayName(atPath: applicationURL.path)
    }

    init(bundleID: String, applicationURL: URL? = nil, displayName: String? = nil) {
        self.bundleID = bundleID
        self.applicationURL = applicationURL ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        self.resolvedDisplayName = displayName
    }
}

struct ApplicationLookupProvider {
    private let fileManager: FileManager
    private let workspace: NSWorkspace

    init(fileManager: FileManager = .default, workspace: NSWorkspace = .shared) {
        self.fileManager = fileManager
        self.workspace = workspace
    }

    func applicationCatalog(runningApplications: [NSRunningApplication]) -> [ExcludedApplicationInfo] {
        var candidatesByBundleID: [String: ExcludedApplicationInfo] = [:]

        for app in runningApplications {
            guard let bundleID = app.bundleIdentifier else { continue }
            candidatesByBundleID[bundleID] = ExcludedApplicationInfo(
                bundleID: bundleID,
                applicationURL: app.bundleURL ?? workspace.urlForApplication(withBundleIdentifier: bundleID),
                displayName: app.localizedName
            )
        }

        for url in installedApplicationURLs() {
            guard let bundleID = Bundle(url: url)?.bundleIdentifier else { continue }
            candidatesByBundleID[bundleID] = candidatesByBundleID[bundleID]
                ?? ExcludedApplicationInfo(bundleID: bundleID, applicationURL: url)
        }

        return candidatesByBundleID.values.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    func search(
        query: String,
        in catalog: [ExcludedApplicationInfo],
        includeUnresolvedBundleID: Bool = true,
        limit: Int = 6
    ) -> [ExcludedApplicationInfo] {
        guard let normalizedQuery = ActivationMonitor.normalizeBundleID(query) else {
            return []
        }

        var scoredResults = catalog.compactMap { application -> (ExcludedApplicationInfo, Int)? in
            guard let score = fuzzyScore(application: application, query: normalizedQuery) else {
                return nil
            }
            return (application, score)
        }

        if includeUnresolvedBundleID,
           looksLikeBundleID(normalizedQuery),
           scoredResults.isEmpty,
           !scoredResults.contains(where: { $0.0.bundleID == normalizedQuery }) {
            scoredResults.append((ExcludedApplicationInfo(bundleID: normalizedQuery), 70))
        }

        return scoredResults
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 {
                    return lhs.1 > rhs.1
                }
                return lhs.0.displayName.localizedCaseInsensitiveCompare(rhs.0.displayName) == .orderedAscending
            }
            .prefix(limit)
            .map(\.0)
    }

    private func installedApplicationURLs() -> [URL] {
        let homeDirectory = fileManager.homeDirectoryForCurrentUser
        let roots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Library/CoreServices", isDirectory: true),
            homeDirectory.appendingPathComponent("Applications", isDirectory: true)
        ]

        var urls: [URL] = []

        for root in roots where fileManager.fileExists(atPath: root.path) {
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isApplicationKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else {
                continue
            }

            for case let url as URL in enumerator where url.pathExtension == "app" {
                urls.append(url)
            }
        }

        return urls
    }

    private func fuzzyScore(application: ExcludedApplicationInfo, query: String) -> Int? {
        let normalizedQuery = query.normalizedForAppLookup
        guard !normalizedQuery.isEmpty else {
            return nil
        }

        let searchableValues = [
            application.displayName,
            application.applicationURL?.deletingPathExtension().lastPathComponent,
            application.bundleID
        ]
        .compactMap { $0?.normalizedForAppLookup }

        var bestScore: Int?

        for value in searchableValues {
            let score: Int?
            if value == normalizedQuery {
                score = 100
            } else if value.hasPrefix(normalizedQuery) {
                score = 90
            } else if value.contains(normalizedQuery) {
                score = 80
            } else if value.isSubsequenceMatch(for: normalizedQuery) {
                score = 50
            } else {
                score = nil
            }

            if let score {
                bestScore = max(bestScore ?? 0, score)
            }
        }

        return bestScore
    }

    private func looksLikeBundleID(_ value: String) -> Bool {
        value.contains(".") && value.rangeOfCharacter(from: .whitespacesAndNewlines) == nil
    }
}

private extension String {
    var normalizedForAppLookup: String {
        folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    func isSubsequenceMatch(for query: String) -> Bool {
        var searchIndex = startIndex

        for character in query {
            guard let matchIndex = self[searchIndex...].firstIndex(of: character) else {
                return false
            }
            searchIndex = index(after: matchIndex)
        }

        return true
    }
}
