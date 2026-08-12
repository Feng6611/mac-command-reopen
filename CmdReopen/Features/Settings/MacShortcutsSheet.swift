//
//  MacShortcutsSheet.swift
//  CmdReopen
//

import SwiftUI

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
    @ObservedObject private var appLanguage = AppLanguage.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: DS.Spacing.xl) {
                    section(
                        title: appLanguage.string(localized: "Apps",
                            comment: "Section of the Mac shortcuts sheet covering app-level shortcuts."),
                        shortcuts: Self.appShortcuts
                    )

                    VStack(alignment: .leading, spacing: DS.Spacing.md) {
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
                .padding(DS.Spacing.xl)
            }
        }
        .frame(width: 460, height: 560)
    }

    private var header: some View {
        HStack {
            Text(appLanguage.string(localized: "Mac window shortcuts",
                comment: "Title of the sheet listing the macOS window shortcuts."))
                .font(.headline)

            Spacer(minLength: 0)

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel(appLanguage.string("Close"))
        }
        .padding(.horizontal, DS.Spacing.xl)
        .padding(.vertical, DS.Spacing.lg)
    }

    private func section(title: String, shortcuts: [MacShortcut]) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            VStack(spacing: DS.Spacing.xs) {
                ForEach(shortcuts) { shortcut in
                    HStack(spacing: DS.Spacing.md) {
                        keyCaps(for: shortcut)
                        Text(shortcut.label(appLanguage))
                            .font(.callout)
                        Spacer(minLength: 0)
                    }
                }
            }
        }
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
        .padding(DS.Spacing.lg)
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
                .frame(width: 108, alignment: .leading)
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
        .frame(width: 96, alignment: .leading)
    }
}

/// One row of the sheet.
///
/// `glyphs` are the key faces to draw. A shortcut whose key moves with the
/// keyboard layout carries none — see `windowShortcuts`.
struct MacShortcut: Identifiable {
    let id: String
    let glyphs: [String]
    let label: (AppLanguage) -> String
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
        // glyph would be wrong for a good share of users. The label carries
        // the meaning, which is the part that does not move.
        MacShortcut(id: "switchWindows", glyphs: []) {
            $0.string(localized: "Switch windows within an app — ⌘ and the key above Tab",
                comment: "Label for the shortcut that cycles windows of the frontmost app; its key differs by keyboard layout.")
        },
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
