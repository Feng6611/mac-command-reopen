//
//  DesignSystem.swift
//  CmdReopen
//
//  Design tokens and reusable components.
//  Strategy: native-first — use Apple system colors, fonts, and controls.
//  Only define what Apple doesn't provide: the spacing scale, the brand
//  colour and its tints, and the few components used across features.
//
//  Rules (see DESIGN.md):
//  1. Native-first — default to system components.
//  2. Rule of 3 — token must appear ≥3 times to live here.
//  3. Zero-sum — add one, delete one.
//
import SwiftUI

// MARK: - Design Tokens

enum DS {

    // MARK: Spacing (4pt base grid)

    enum Spacing {
        static let xxs:  CGFloat = 2
        static let xs:   CGFloat = 4
        static let sm:   CGFloat = 8
        static let md:   CGFloat = 12
        static let lg:   CGFloat = 16
        static let xl:   CGFloat = 20
        static let xxl:  CGFloat = 24
        static let xxxl: CGFloat = 32
    }

    // MARK: Window Dimensions

    /// Settings geometry lives here because two Kiki call sites have to agree
    /// on it: `KikiSettingsWindowController` sizes the AppKit window, and
    /// `KikiSettingsCoordinatorView` sizes the SwiftUI content — and the
    /// SwiftUI ideal is what the window actually settles at. Passing one and
    /// not the other is how this pane ended up at Kiki's generic default.
    enum Window {
        /// Kiki fixes menu-bar utility Settings at 500 (min == ideal == max).
        /// Passing anything else here only produces a window whose minimum
        /// contradicts its maximum.
        static let settingsWidth: CGFloat = 500

        /// The pane may be resized down without collapsing the tab chrome;
        /// longer General/About content then scrolls inside the native pane.
        static let settingsMinimumHeight: CGFloat = 520

        /// Compact enough to stay a utility window. General intentionally
        /// scrolls once the exclusion list grows instead of making every tab
        /// inherit a tall document-like window.
        static let settingsHeight: CGFloat = 620
    }

    // MARK: Corner Radius (semantic)

    enum Radius {
        static let control: CGFloat = 6
        static let card:    CGFloat = 10
    }

    // MARK: Semantic Colors

    enum Colors {
        static let cardBorder = Color(nsColor: .separatorColor).opacity(0.4)

        static let brandPrimary = Color(red: 203/255, green: 48/255, blue: 224/255)
        static let accentTint   = brandPrimary.opacity(0.12)
    }

    // MARK: Typography (only non-system fonts)
    // Prefer .headline / .body / .callout / .caption / .footnote for everything else.

    enum Typography {
        static let displayHero   = Font.system(size: 36, weight: .bold, design: .rounded)
        static let metricValue   = Font.system(size: 16, weight: .semibold, design: .rounded)
        static let micro         = Font.system(size: 10)
        static let microSemibold = Font.system(size: 10, weight: .semibold)
    }
}

// MARK: - Stats GroupBox Style

struct DSStatsGroupBoxStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            configuration.label
            configuration.content
        }
        .padding(DS.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.3), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.03), radius: 4, x: 0, y: 1)
    }
}

extension GroupBoxStyle where Self == DSStatsGroupBoxStyle {
    static var dsStats: DSStatsGroupBoxStyle { DSStatsGroupBoxStyle() }
}

// MARK: - Section Header

struct SectionHeader<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                if let subtitle {
                    Text(subtitle)
                        .font(DS.Typography.micro)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            trailing()
        }
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = { EmptyView() }
    }
}

// MARK: - Metric Tile

struct MetricTile: View {
    let title: String
    let value: String
    let systemImage: String
    var tint: Color = .accentColor

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)

            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(DS.Typography.metricValue)
                    .foregroundStyle(.primary)
                    .monospacedDigit()
                Text(title)
                    .font(DS.Typography.microSemibold)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(minWidth: 64, alignment: .leading)
        .padding(.horizontal, DS.Spacing.md)
        .padding(.vertical, DS.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.3), lineWidth: 0.5)
        )
    }
}

// MARK: - Empty State

struct EmptyStateView: View {
    let systemImage: String
    let text: String

    var body: some View {
        VStack(spacing: DS.Spacing.xs) {
            Image(systemName: systemImage)
                .font(.system(size: 18))
                .foregroundStyle(.secondary.opacity(0.48))
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
    }
}
