//
//  HelperProcessFilter.swift
//  CmdReopen
//
//  Created by Claude on 2026/7/21.
//

import Foundation

/// Identifies background helper processes (login items, app-nested helpers).
/// Their activations are not deliberate user switches and their windows are
/// managed by a parent app, so reopening them is noise — and counting them as
/// restored windows makes the stats untrustworthy ("Xnip Helper" in Top Apps).
enum HelperProcessFilter {
    static func isHelperLike(bundleID: String?, bundleURL: URL?, localizedName: String?) -> Bool {
        if let bundleURL, isNestedInsideAppBundle(bundleURL) {
            return true
        }
        if let bundleID {
            let normalizedID = bundleID.lowercased()
            if normalizedID.contains(".helper") || normalizedID.hasSuffix("helper") {
                return true
            }
        }
        if let localizedName, localizedName.hasSuffix(" Helper") {
            return true
        }
        return false
    }

    private static func isNestedInsideAppBundle(_ url: URL) -> Bool {
        url.path.range(of: ".app/Contents/", options: .caseInsensitive) != nil
    }
}
