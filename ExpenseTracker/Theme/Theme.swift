import SwiftUI
import UIKit

extension Color {
    /// Colour that adapts to light / dark mode.
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { trait in
            UIColor(hex: trait.userInterfaceStyle == .dark ? dark : light)
        })
    }

    init(hex: UInt32) { self.init(uiColor: UIColor(hex: hex)) }
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: alpha)
    }
}

enum Theme {
    // Brand
    static let accent = Color.accentColor
    static let emerald = Color(light: 0x059669, dark: 0x34D399)
    static let emeraldSoft = Color(light: 0xD1FAE5, dark: 0x0F3B2E)

    // Surfaces – very slightly green-tinted neutrals.
    static let background = Color(light: 0xF3F6F4, dark: 0x090D0B)
    static let card = Color(light: 0xFFFFFF, dark: 0x131A17)
    static let cardStroke = Color(light: 0x0B1411, dark: 0xFFFFFF).opacity(0.06)
    static let elevated = Color(light: 0xF6F9F7, dark: 0x1A2320)

    // Semantic
    static let income = Color(light: 0x059669, dark: 0x34D399)
    static let warning = Color(light: 0xD97706, dark: 0xFBBF24)
    static let danger = Color(light: 0xDC2626, dark: 0xF87171)

    static let heroGradient = LinearGradient(
        colors: [Color(light: 0x10B981, dark: 0x0E7A5A),
                 Color(light: 0x047857, dark: 0x064E3B),
                 Color(light: 0x064E3B, dark: 0x052E24)],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    static let cornerRadius: CGFloat = 22
}

// MARK: - Card

struct CardModifier: ViewModifier {
    var padding: CGFloat = 18
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .strokeBorder(Theme.cardStroke, lineWidth: 1))
            .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
    }
}

extension View {
    func card(padding: CGFloat = 18) -> some View { modifier(CardModifier(padding: padding)) }

    /// Gentle fade + rise when a view first appears; `delay` staggers sections.
    func appearAnimation(delay: Double = 0) -> some View { modifier(AppearModifier(delay: delay)) }

    func themedBackground() -> some View {
        background(Theme.background.ignoresSafeArea())
    }
}

private struct AppearModifier: ViewModifier {
    let delay: Double
    @State private var shown = false
    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 14)
            .onAppear {
                withAnimation(.spring(response: 0.55, dampingFraction: 0.85).delay(delay)) { shown = true }
            }
    }
}

// MARK: - Small reusable pieces

struct SectionTitle: View {
    let title: String
    var trailing: String?
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.headline)
            Spacer()
            if let trailing {
                Text(trailing).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}

/// Rounded-square icon tile, used for categories and settings rows.
struct IconTile: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 40
    var filled = false
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(filled ? .white : color)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                    .fill(filled ? AnyShapeStyle(color.gradient) : AnyShapeStyle(color.opacity(0.14)))
            )
    }
}

struct Pill: View {
    let text: String
    var symbol: String?
    var color: Color = Theme.emerald
    var body: some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol) }
            Text(text)
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 10).padding(.vertical, 5)
        .foregroundStyle(color)
        .background(color.opacity(0.14), in: Capsule())
    }
}
