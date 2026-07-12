import SwiftUI

/// Groove's visual language, mirroring the groove-catalog studio brand so the
/// phone app and the web studio read as one product: near-black surfaces, a
/// teal primary accent, and a warm gold for confirmed / owned states.
enum Brand {
    static let bg = Color(hex: 0x0B0B0B)
    static let surface = Color(hex: 0x121212)
    static let card = Color(hex: 0x161616)
    static let cardElevated = Color(hex: 0x1E1E1E)
    static let border = Color(hex: 0x252525)
    static let text = Color(hex: 0xF2F2F2)
    static let muted = Color(hex: 0x8A8A8A)

    static let teal = Color(hex: 0x4FD1D9)
    static let gold = Color(hex: 0xC5A059)
    static let ok = Color(hex: 0x6BC9A8)
    static let warn = Color(hex: 0xE8A04A)
    static let err = Color(hex: 0xE07070)

    /// Primary interactive accent.
    static let accent = teal
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

// MARK: - Card surface

private struct CardBackground: ViewModifier {
    var elevated = false
    func body(content: Content) -> some View {
        content
            .background(elevated ? Brand.cardElevated : Brand.card)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Brand.border, lineWidth: 1)
            )
    }
}

extension View {
    /// Wrap content in the standard Groove card surface.
    func grooveCard(elevated: Bool = false) -> some View {
        modifier(CardBackground(elevated: elevated))
    }

    /// Standard screen background that ignores safe areas.
    func grooveScreenBackground() -> some View {
        background(Brand.bg.ignoresSafeArea())
    }
}
