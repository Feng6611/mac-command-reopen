//
//  HelperProcessFilter.swift
//  CmdReopen
//
//  Created by Claude on 2026/7/21.
//

import AppKit
import Foundation

/// Identifies background helper processes without rejecting user-facing apps
/// merely because another app bundles them. Some ordinary foreground apps,
/// including Simulator and Feishu Meetings, live inside a parent app bundle.
enum HelperProcessFilter {
    static func isHelperLike(
        bundleID: String?,
        bundleURL: URL?,
        localizedName: String?,
        activationPolicy: NSApplication.ActivationPolicy? = nil
    ) -> Bool {
        // Strong identity signals remain authoritative even if a helper
        // temporarily reports a regular activation policy.
        if let bundleID {
            let normalizedID = bundleID.lowercased()
            if normalizedID.contains(".helper") || normalizedID.hasSuffix("helper") {
                return true
            }
        }
        if let localizedName, localizedName.hasSuffix(" Helper") {
            return true
        }

        // A nested path alone is only a weak helper signal. Runtime activation
        // policy is authoritative for apps that participate in normal macOS
        // foreground switching. Without runtime evidence, stay conservative.
        if let bundleURL, isNestedInsideAppBundle(bundleURL) {
            return activationPolicy != .regular
        }
        return false
    }

    private static func isNestedInsideAppBundle(_ url: URL) -> Bool {
        url.path.range(of: ".app/Contents/", options: .caseInsensitive) != nil
    }
}
