//
//  MacShortcutsSheet.swift
//  CmdReopen
//

import SwiftUI

/// Reports the height the list wants, so the sheet is as tall as what it holds
/// instead of a number someone guessed. Measured inside the scroll view, where
/// the content is laid out at its natural height whatever the sheet resolves
/// to, so the value cannot feed back into the frame that consumes it.
private struct MacShortcutsContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// The window language macOS already speaks, with the one place this app fills
/// in marked inside it.
///
/// Not a manual bolted onto the product: Command Reopen appears as a note
/// under `⌘M`, in the section where that shortcut lives, rather than as a
/// feature summary at the end. A user who reads this should conclude on their
/// own that the app occupies one line of a language they already have — which
/// is also the answer to every "could it also do windows layouts / split view
/// / custom shortcuts" that will ever arrive.
struct MacShortcutsSheet: View {
    /// Narrower than the 500pt Settings window it drops out of, so the parent
    /// still reads as the window this belongs to.
    private static let width: CGFloat = 440

    /// Floor and ceiling for the measured content. The ceiling keeps the sheet
    /// clear of the Settings window's bottom edge — a sheet as tall as its
    /// parent reads as a second window in the wrong place. Past it the list
    /// scrolls, which is what the longer locales need.
    private static let minimumContentHeight: CGFloat = 320
    private static let maximumContentHeight: CGFloat = 480

    @ObservedObject private var appLanguage = AppLanguage.shared
    @State private var contentHeight: CGFloat = MacShortcutsSheet.maximumContentHeight

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                    section(
                        title: appLanguage.string(localized: "Apps",
                            comment: "Section of the Mac shortcuts sheet covering app-level shortcuts."),
                        shortcuts: Self.appShortcuts
                    )

                    VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                        section(
                            title: appLanguage.string(localized: "Windows",
                                comment: "Section of the Mac shortcuts sheet covering window-level shortcuts."),
                            shortcuts: Self.windowShortcuts
                        )
                        // Directly under ⌘M, the shortcut it annotates. At the
                        // bottom of the sheet it would read as this app's
                        // feature list; here it reads as a footnote to one line
                        // of the system's own language.
                        gapNote
                    }

                    section(
                        title: appLanguage.string(localized: "Spaces",
                            comment: "Section of the Mac shortcuts sheet covering Mission Control and Spaces."),
                        shortcuts: Self.spaceShortcuts
                    )
                }
                .padding(DS.Spacing.lg)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: MacShortcutsContentHeightKey.self,
                            value: proxy.size.height
                        )
                    }
                )
            }
            .frame(height: resolvedContentHeight)

        }
        .frame(width: Self.width)
        .onPreferenceChange(MacShortcutsContentHeightKey.self) { height in
            guard height > 0 else { return }
            contentHeight = height
        }
    }

    private var resolvedContentHeight: CGFloat {
        min(max(contentHeight, Self.minimumContentHeight), Self.maximumContentHeight)
    }

    private var header: some View {
        Text(appLanguage.string(localized: "Mac window shortcuts",
            comment: "Title of the sheet listing the macOS window shortcuts."))
            .font(.headline)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DS.Spacing.xl)
            .padding(.trailing, 36)
            .padding(.vertical, DS.Spacing.lg)
    }

    private func section(title: String, shortcuts: [MacShortcut]) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            VStack(spacing: DS.Spacing.xxs) {
                ForEach(shortcuts) { shortcut in
                    row(for: shortcut)
                }
            }
        }
    }

    /// Label left, keys against the trailing edge — the arrangement System
    /// Settings uses for its own shortcut lists. A leading key column has to be
    /// wide enough for the widest combination, which leaves an empty gutter
    /// beside every row whose key is not printable and forces the long labels
    /// to wrap inside what is left of the row.
    private func row(for shortcut: MacShortcut) -> some View {
        HStack(alignment: .center, spacing: DS.Spacing.md) {
            VStack(alignment: .leading, spacing: 1) {
                Text(shortcut.label(appLanguage))
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)

                if let detail = shortcut.detail?(appLanguage) {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: DS.Spacing.md)

            keyCaps(for: shortcut)
        }
        .frame(minHeight: 26)
    }

    /// The one thing this app does, phrased as a before and after rather than
    /// as a feature: the row above states what the user pressed, these two
    /// lines state what each of macOS and this app does about it.
    private var gapNote: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            HStack(spacing: DS.Spacing.xs) {
                Text(verbatim: "⌘M")
                    .font(.callout.weight(.semibold))
                Text(appLanguage.string(localized: "then",
                    comment: "Joins two shortcuts pressed one after the other, as in “⌘M then ⌘⇥”."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(verbatim: "⌘⇥")
                    .font(.callout.weight(.semibold))
            }

            outcome(
                source: "macOS",
                result: appLanguage.string(localized: "The app comes back. The window stays in the Dock.",
                    comment: "What macOS does after minimizing a window and switching back to the app."),
                isApp: false
            )
            outcome(
                source: "Command Reopen",
                result: appLanguage.string(localized: "The window comes back with it.",
                    comment: "What this app does after minimizing a window and switching back to the app."),
                isApp: true
            )
        }
        .padding(DS.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .fill(DS.Colors.accentTint)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .strokeBorder(DS.Colors.brandPrimary.opacity(0.35), lineWidth: 1)
        )
    }

    /// `source` is a product name — never localized, like the names themselves.
    private func outcome(source: String, result: String, isApp: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.sm) {
            Text(verbatim: source)
                .font(.caption.weight(.medium))
                .foregroundStyle(isApp ? DS.Colors.brandPrimary : .secondary)
                .frame(width: 96, alignment: .leading)
            Text(result)
                .font(.caption)
                .foregroundStyle(isApp ? .primary : .secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    /// Key faces, sized for a list rather than the onboarding demo's hero
    /// treatment. Glyphs stay verbatim in every locale, like the keys do.
    private func keyCaps(for shortcut: MacShortcut) -> some View {
        HStack(spacing: 3) {
            ForEach(Array(shortcut.glyphs.enumerated()), id: \.offset) { _, glyph in
                Text(verbatim: glyph)
                    .font(.callout)
                    .frame(minWidth: 26, minHeight: 26)
                    .padding(.horizontal, 4)
                    .background(
                        RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                            .strokeBorder(DS.Colors.cardBorder, lineWidth: 1)
                    )
            }
        }
        .fixedSize()
    }
}

/// One row of the sheet.
///
/// `glyphs` are the key faces to draw. A shortcut whose key moves with the
/// keyboard layout carries none and names its key in `detail` instead — see
/// `windowShortcuts`.
struct MacShortcut: Identifiable {
    let id: String
    let glyphs: [String]
    let label: (AppLanguage) -> String
    var detail: ((AppLanguage) -> String)?
}

extension MacShortcutsSheet {
    static let appShortcuts: [MacShortcut] = [
        MacShortcut(id: "switchApps", glyphs: ["⌘", "⇥"]) {
            $0.string(localized: "Switch apps", comment: "Label for the ⌘⇥ shortcut.")
        },
        MacShortcut(id: "hideApp", glyphs: ["⌘", "H"]) {
            $0.string(localized: "Hide the app", comment: "Label for the ⌘H shortcut.")
        },
        MacShortcut(id: "quitApp", glyphs: ["⌘", "Q"]) {
            $0.string(localized: "Quit the app", comment: "Label for the ⌘Q shortcut.")
        }
    ]

    static let windowShortcuts: [MacShortcut] = [
        // Drawn without key faces on purpose: the key below Escape is ` on a
        // US layout, ^ on a German one and @ on a French one, so a printed
        // glyph would be wrong for a good share of users. The detail line
        // carries the meaning, which is the part that does not move.
        MacShortcut(
            id: "switchWindows",
            glyphs: [],
            label: {
                $0.string(localized: "Switch windows within an app",
                    comment: "Label for the shortcut that cycles windows of the frontmost app.")
            },
            detail: {
                $0.string(localized: "⌘ and the key above Tab",
                    comment: "Names the keys for the window-cycling shortcut, whose second key differs by keyboard layout. Keep ⌘ verbatim.")
            }
        ),
        MacShortcut(id: "closeWindow", glyphs: ["⌘", "W"]) {
            $0.string(localized: "Close the window", comment: "Label for the ⌘W shortcut.")
        },
        MacShortcut(id: "minimizeWindow", glyphs: ["⌘", "M"]) {
            $0.string(localized: "Minimize the window", comment: "Label for the ⌘M shortcut.")
        }
    ]

    // Names match Apple's own, per locale. A term invented here would cost
    // this sheet the only thing it has to offer, which is knowing the system.
    static let spaceShortcuts: [MacShortcut] = [
        MacShortcut(id: "switchSpaces", glyphs: ["⌃", "←", "→"]) {
            $0.string(localized: "Switch Spaces", comment: "Label for the ⌃← / ⌃→ shortcut. Use Apple's own term for Spaces in this locale.")
        },
        MacShortcut(id: "missionControl", glyphs: ["⌃", "↑"]) {
            $0.string(localized: "Mission Control", comment: "Label for the ⌃↑ shortcut. Use Apple's own name for Mission Control in this locale.")
        },
        MacShortcut(id: "appExpose", glyphs: ["⌃", "↓"]) {
            $0.string(localized: "App Exposé", comment: "Label for the ⌃↓ shortcut. Use Apple's own name for App Exposé in this locale.")
        }
    ]
}
