//
//  DesignSystem.swift
//  ComTab
//
//  Design tokens and reusable components.
//  Strategy: use Apple-native colors/fonts/controls directly;
//  only define what Apple doesn't provide (spacing scale, semantic
//  color aliases for opacity combos, card modifier, small components).
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

    // MARK: Corner Radius

    enum Radius {
        static let sm:   CGFloat = 6
        static let smMd: CGFloat = 8
        static let md:   CGFloat = 10
        static let lg:   CGFloat = 14
        static let xl:   CGFloat = 18
    }

    // MARK: Semantic Colors (only aliases for opacity combos)

    enum Colors {
        // Backgrounds
        static let cardBackground = Color(nsColor: .windowBackgroundColor)

        // Borders
        static let cardBorder = Color(nsColor: .separatorColor).opacity(0.5)
        static let cardBorderSubtle = Color(nsColor: .separatorColor).opacity(0.4)

        // Accent tints
        static let accentTint = Color.accentColor.opacity(0.12)
        static let accentTintSubtle = Color.accentColor.opacity(0.06)

        // Pro — Lifetime uses accent (purple), Yearly uses blue
        static let lifetimeTint = Color.accentColor.opacity(0.10)
        static let lifetimeFill = Color.accentColor.opacity(0.88)
        static let yearlyTint   = Color.blue.opacity(0.10)
        static let yearlyFill   = Color.blue.opacity(0.82)
        static let proTint      = lifetimeTint
        static let proFill      = lifetimeFill

        // Warning
        static let warningTint = Color.orange.opacity(0.15)
        static let warningFill = Color.orange.opacity(0.1)
        static let warningBorder = Color.orange.opacity(0.3)

        // Text
        static let textTertiary = Color.secondary.opacity(0.5)
    }

    // MARK: Typography

    enum Typography {
        static let headlineMedium = Font.system(size: 20, weight: .semibold)
        static let headlineSmall  = Font.system(size: 18, weight: .bold, design: .rounded)

        static let bodyLarge  = Font.system(size: 14, weight: .semibold)
        static let bodyMedium = Font.system(size: 13, weight: .medium)
        static let body       = Font.system(size: 13)
        static let bodySmall  = Font.system(size: 12, weight: .medium)

        static let caption       = Font.system(size: 11)
        static let captionMedium = Font.system(size: 11, weight: .medium)

        static let micro         = Font.system(size: 10)
        static let microSemibold = Font.system(size: 10, weight: .semibold)

        // Stats hero
        static let displayLarge = Font.system(size: 36, weight: .bold, design: .rounded)

        // Letter-specific
        static let letterHeadline  = Font.system(size: 18, weight: .regular)
        static let letterBody      = Font.system(size: 13)
        static let letterSignature = Font.system(size: 14, weight: .medium)
        static let letterLabel     = Font.system(size: 12, weight: .semibold)
    }

}

// MARK: - Card Modifier

struct DSCardModifier: ViewModifier {
    var borderColor: Color = DS.Colors.cardBorder
    var radius: CGFloat = DS.Radius.lg

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(DS.Colors.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 1)
            )
    }
}

// MARK: - Glass Card Modifier (uses system material for depth)

struct DSGlassCardModifier: ViewModifier {
    var borderColor: Color = DS.Colors.cardBorder
    var radius: CGFloat = DS.Radius.lg

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 12.0, *) {
            content
                .background(
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(.regularMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(borderColor, lineWidth: 1)
                )
        } else {
            content.modifier(DSCardModifier(borderColor: borderColor, radius: radius))
        }
    }
}

extension View {
    func dsCard(borderColor: Color = DS.Colors.cardBorder, radius: CGFloat = DS.Radius.lg) -> some View {
        modifier(DSCardModifier(borderColor: borderColor, radius: radius))
    }

    func dsGlassCard(borderColor: Color = DS.Colors.cardBorder, radius: CGFloat = DS.Radius.lg) -> some View {
        modifier(DSGlassCardModifier(borderColor: borderColor, radius: radius))
    }
}

// MARK: - Icon Badge

struct DSIconBadge: View {
    let systemName: String
    var iconColor: Color = .accentColor
    var backgroundColor: Color = DS.Colors.accentTint
    var size: CGFloat = 42
    var iconSize: CGFloat = 18

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

// MARK: - Dot Separator

struct DSDotSeparator: View {
    var body: some View {
        Circle()
            .fill(Color.secondary.opacity(0.4))
            .frame(width: 3, height: 3)
    }
}

// MARK: - onChange backward-compatibility shim (macOS 12+)

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
