//
//  WindowInspector.swift
//  CmdReopen
//
//  Created by Codex on 2026/4/26.
//

import CoreGraphics
import Foundation

struct WindowInspectionReport: Equatable {
    let hasVisibleWindow: Bool
    let totalWindowsForApp: Int
    let onScreenWindows: Int
    let visibleCandidateWindows: Int
    let transparentWindows: Int
    let nonStandardLayerWindows: Int
    let tinyWindows: Int
}

enum WindowInspector {
    static let minimumVisibleWindowDimension: CGFloat = 32

    static func visibleWindowReport(
        ownerPID: pid_t,
        windowInfoList: [[String: Any]],
        minimumDimension: CGFloat = minimumVisibleWindowDimension
    ) -> WindowInspectionReport {
        var totalWindowsForApp = 0
        var onScreenWindows = 0
        var visibleCandidateWindows = 0
        var transparentWindows = 0
        var nonStandardLayerWindows = 0
        var tinyWindows = 0

        for windowInfo in windowInfoList {
            guard let windowPID = windowOwnerPID(from: windowInfo),
                  windowPID == ownerPID else {
                continue
            }
            totalWindowsForApp += 1

            let isOnScreen = (windowInfo[kCGWindowIsOnscreen as String] as? Bool) ?? true
            guard isOnScreen else {
                continue
            }
            onScreenWindows += 1

            let alpha = (windowInfo[kCGWindowAlpha as String] as? NSNumber)?.doubleValue
                ?? (windowInfo[kCGWindowAlpha as String] as? Double)
                ?? 1
            guard alpha > 0 else {
                transparentWindows += 1
                continue
            }

            let layer = (windowInfo[kCGWindowLayer as String] as? NSNumber)?.intValue
                ?? (windowInfo[kCGWindowLayer as String] as? Int)
                ?? 0
            guard layer == 0 else {
                nonStandardLayerWindows += 1
                continue
            }

            guard let bounds = windowBounds(from: windowInfo) else {
                continue
            }

            guard bounds.width >= minimumDimension && bounds.height >= minimumDimension else {
                tinyWindows += 1
                continue
            }

            visibleCandidateWindows += 1
        }

        return WindowInspectionReport(
            hasVisibleWindow: visibleCandidateWindows > 0,
            totalWindowsForApp: totalWindowsForApp,
            onScreenWindows: onScreenWindows,
            visibleCandidateWindows: visibleCandidateWindows,
            transparentWindows: transparentWindows,
            nonStandardLayerWindows: nonStandardLayerWindows,
            tinyWindows: tinyWindows
        )
    }

    static func hasVisibleWindow(
        ownerPID: pid_t,
        windowInfoList: [[String: Any]],
        minimumDimension: CGFloat = minimumVisibleWindowDimension
    ) -> Bool {
        visibleWindowReport(
            ownerPID: ownerPID,
            windowInfoList: windowInfoList,
            minimumDimension: minimumDimension
        ).hasVisibleWindow
    }

    static func windowOwnerPID(from windowInfo: [String: Any]) -> pid_t? {
        if let pidNumber = windowInfo[kCGWindowOwnerPID as String] as? NSNumber {
            return pid_t(pidNumber.int32Value)
        }
        if let pid = windowInfo[kCGWindowOwnerPID as String] as? pid_t {
            return pid
        }
        if let pid = windowInfo[kCGWindowOwnerPID as String] as? Int32 {
            return pid_t(pid)
        }
        if let pid = windowInfo[kCGWindowOwnerPID as String] as? Int {
            return pid_t(pid)
        }
        return nil
    }

    static func windowBounds(from windowInfo: [String: Any]) -> CGRect? {
        guard let boundsDictionary = windowInfo[kCGWindowBounds as String] as? NSDictionary else {
            return nil
        }

        var bounds = CGRect.zero
        guard CGRectMakeWithDictionaryRepresentation(boundsDictionary, &bounds) else {
            return nil
        }

        return bounds
    }
}
