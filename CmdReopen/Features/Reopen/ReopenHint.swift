//
//  ReopenHint.swift
//  CmdReopen
//

import AppKit
import SwiftUI

/// The two moments the app speaks up on its own while it is new (I-008).
///
/// A utility that works by making Cmd+Tab behave as expected is invisible when
/// it succeeds, and unused when the user never closes a window and comes back.
/// So it says what it did once, the first time it restores a window, and —
/// until that has happened — points out the one moment it could have helped:
/// the user just closed or minimized an app's last window. Each is rare and
/// stops for good; neither asks for anything.
enum ReopenHintPolicy {
    static let firstSuccessShownKey = "cmdreopenHintFirstSuccessShown"
    static let returnTipDaysKey = "cmdreopenHintReturnTipDays"
    /// The tip shows on at most this many days, once each.
    static let returnTipDayLimit = 2

    /// The first restore, said once.
    static func shouldShowFirstSuccess(totalReopens: Int, defaults: UserDefaults) -> Bool {
        totalReopens >= 1 && !defaults.bool(forKey: firstSuccessShownKey)
    }

    static func markFirstSuccessShown(defaults: UserDefaults) {
        defaults.set(true, forKey: firstSuccessShownKey)
    }

    /// The return tip: only before the first restore, once a day, on at most
    /// two days.
    static func shouldShowReturnTip(totalReopens: Int, today: String, defaults: UserDefaults) -> Bool {
        guard totalReopens == 0 else { return false }
        let days = defaults.stringArray(forKey: returnTipDaysKey) ?? []
        return days.count < returnTipDayLimit && !days.contains(today)
    }

    static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static func markReturnTipShown(today: String, defaults: UserDefaults) {
        var days = defaults.stringArray(forKey: returnTipDaysKey) ?? []
        guard !days.contains(today) else { return }
        days.append(today)
        defaults.set(days, forKey: returnTipDaysKey)
    }
}

/// Shows the hints in a small panel at the top right of the screen, where
/// macOS shows notifications.
///
/// Not a user notification: that needs a permission prompt the app otherwise
/// never asks for. Not a popover on the menu bar icon: the status item belongs
/// to KikiMenuBar and the icon can be hidden. The panel never takes focus, so
/// it cannot disturb the Cmd+Tab order the app exists to fix.
@MainActor
final class ReopenHintPresenter {
    private let defaults: UserDefaults
    private let isOnboardingComplete: () -> Bool
    private var panel: NSPanel?
    private var dismissWorkItem: DispatchWorkItem?

    private static let visibleDuration: TimeInterval = 6

    init(defaults: UserDefaults = .standard, isOnboardingComplete: @escaping () -> Bool) {
        self.defaults = defaults
        self.isOnboardingComplete = isOnboardingComplete
    }

    /// Call after each successful restore.
    func reopenSucceeded(totalReopens: Int) {
        guard isOnboardingComplete(),
              ReopenHintPolicy.shouldShowFirstSuccess(totalReopens: totalReopens, defaults: defaults) else { return }
        ReopenHintPolicy.markFirstSuccessShown(defaults: defaults)
        let language = AppLanguage.shared
        show(
            title: language.string(localized: "Window restored",
                comment: "Title of the one-time hint after Command Reopen restores its first window."),
            message: language.string(localized: "Command Reopen brought it back. It works every time you press Cmd+Tab.",
                comment: "Body of the one-time hint after the first restored window.")
        )
        CommandReopenAnalytics.track(CommandReopenEvent.reopenHintShown(.firstSuccess))
    }

    /// Call when an app's last window just closed or minimized and focus moved on.
    func lastWindowClosed(appName: String?, totalReopens: Int, now: Date = Date()) {
        guard isOnboardingComplete(), let appName, !appName.isEmpty else { return }
        let today = ReopenHintPolicy.dayKey(for: now)
        guard ReopenHintPolicy.shouldShowReturnTip(totalReopens: totalReopens, today: today, defaults: defaults) else {
            return
        }
        ReopenHintPolicy.markReturnTipShown(today: today, defaults: defaults)
        let language = AppLanguage.shared
        show(
            title: language.string(localized: "Cmd+Tab brings it back",
                comment: "Title of the tip shown after an app's last window closed, before the first restore."),
            message: language.string(localized: "Switch back to \(appName) with Cmd+Tab and its window reopens.",
                comment: "Body of the tip after an app's last window closed; %@ is that app's name.")
        )
        CommandReopenAnalytics.track(CommandReopenEvent.reopenHintShown(.returnTip))
    }

    private func show(title: String, message: String) {
        dismiss(animated: false)

        let content = ReopenHintView(title: title, message: message) { [weak self] in
            self?.dismiss(animated: true)
        }
        let hosting = NSHostingView(rootView: content)
        hosting.frame.size = hosting.fittingSize

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: hosting.fittingSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hosting
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]

        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
            ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            let size = hosting.fittingSize
            panel.setFrameOrigin(NSPoint(
                x: visible.maxX - size.width - DS.Spacing.lg,
                y: visible.maxY - size.height - DS.Spacing.sm
            ))
        }

        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            panel.animator().alphaValue = 1
        }
        self.panel = panel

        let workItem = DispatchWorkItem { [weak self] in self?.dismiss(animated: true) }
        dismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.visibleDuration, execute: workItem)
    }

    private func dismiss(animated: Bool) {
        dismissWorkItem?.cancel()
        dismissWorkItem = nil
        guard let panel else { return }
        self.panel = nil
        guard animated else {
            panel.orderOut(nil)
            return
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.orderOut(nil)
        })
    }
}

private struct ReopenHintView: View {
    let title: String
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: DS.Spacing.md) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 32, height: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(title)
                    .font(.headline)
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(DS.Spacing.md)
        .frame(width: 340)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: DS.Radius.modal, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.modal, style: .continuous)
                .strokeBorder(DS.Colors.cardBorder, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onDismiss)
        .accessibilityElement(children: .combine)
    }
}
