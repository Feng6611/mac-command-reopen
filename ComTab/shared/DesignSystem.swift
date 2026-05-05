//
//  DesignSystem.swift
//  ComTab
//
//  Design tokens and reusable components.
//  Strategy: native-first — use Apple system colors, fonts, and controls.
//  Only define what Apple doesn't provide: spacing scale, semantic
//  color aliases, card modifier, and shared UI components.
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

    enum Window {
        static let settingsWidth:  CGFloat = 540
        static let settingsHeight: CGFloat = 480
    }

    // MARK: Corner Radius (semantic)

    enum Radius {
        static let control: CGFloat = 6
        static let card:    CGFloat = 10
        static let modal:   CGFloat = 14
    }

    // MARK: Semantic Colors

    enum Colors {
        static let cardBackground = Color(nsColor: .windowBackgroundColor)
        static let cardBorder     = Color(nsColor: .separatorColor).opacity(0.4)

        static let brandPrimary = Color(red: 203/255, green: 48/255, blue: 224/255)
        static let accentTint       = brandPrimary.opacity(0.12)
        static let accentTintSubtle = brandPrimary.opacity(0.06)
        static let proFill          = brandPrimary.opacity(0.88)

        static let warningTint = Color.orange.opacity(0.12)
    }

    // MARK: Typography (only non-system fonts)
    // Prefer .headline / .body / .callout / .caption / .footnote for everything else.

    enum Typography {
        static let displayHero    = Font.system(size: 36, weight: .bold, design: .rounded)
        static let onboardingTitle = Font.system(size: 24, weight: .bold)
        static let headlineMedium = Font.system(size: 20, weight: .semibold)
        static let headlineSmall  = Font.system(size: 18, weight: .bold, design: .rounded)
        static let metricValue    = Font.system(size: 16, weight: .semibold, design: .rounded)
        static let bodyMedium     = Font.system(size: 13, weight: .medium)
        static let captionMedium  = Font.system(size: 11, weight: .medium)
        static let micro          = Font.system(size: 10)
        static let microSemibold  = Font.system(size: 10, weight: .semibold)
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

// MARK: - Card Modifier (for marketing surfaces: Paywall, Onboarding, Support)

struct DSCardModifier: ViewModifier {
    var borderColor: Color = DS.Colors.cardBorder
    var radius: CGFloat = DS.Radius.card

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(DS.Colors.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 2)
    }
}

extension View {
    func dsCard(borderColor: Color = DS.Colors.cardBorder, radius: CGFloat = DS.Radius.card) -> some View {
        modifier(DSCardModifier(borderColor: borderColor, radius: radius))
    }
}

// MARK: - Icon Badge

struct DSIconBadge: View {
    let systemName: String
    var iconColor: Color = .accentColor
    var backgroundColor: Color = DS.Colors.accentTint
    var size: CGFloat = 44
    var iconSize: CGFloat = 19

    var body: some View {
        ZStack {
            Circle()
                .fill(backgroundColor)
                .frame(width: size, height: size)
            Image(systemName: systemName)
                .font(.system(size: iconSize))
                .foregroundStyle(iconColor)
        }
    }
}

// MARK: - Status Pill

enum PillTone {
    case accent, warning, neutral
}

struct StatusPill: View {
    let text: String
    var tone: PillTone = .accent

    var body: some View {
        Text(text)
            .font(DS.Typography.microSemibold)
            .foregroundColor(foregroundColor)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(fillColor))
    }

    private var foregroundColor: Color {
        switch tone {
        case .accent:  return .white
        case .warning: return .orange
        case .neutral: return .secondary
        }
    }

    private var fillColor: Color {
        switch tone {
        case .accent:  return DS.Colors.proFill
        case .warning: return DS.Colors.warningTint
        case .neutral: return Color(nsColor: .controlBackgroundColor)
        }
    }
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

// MARK: - Dot Separator

struct DSDotSeparator: View {
    var body: some View {
        Circle()
            .fill(Color.secondary.opacity(0.4))
            .frame(width: 3, height: 3)
    }
}

// MARK: - onChange compatibility shim (macOS 13+)

struct OnChangeCompat<V: Equatable>: ViewModifier {
    let value: V
    let action: () -> Void

    func body(content: Content) -> some View {
        if #available(macOS 14.0, *) {
            content.onChange(of: value) { action() }
        } else {
            content.onChange(of: value) { _ in action() }
        }
    }
}
