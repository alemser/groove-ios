import SwiftUI

/// The brief notice an `AmplifierHUD` is drawn as: a capsule at the top of
/// the remote, like the system volume indicator — it says what the amp did
/// without taking over the screen or needing a tap to dismiss.
struct AmplifierHUDView: View {
    let hud: AmplifierHUD

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: hud.symbol)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Brand.accent)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(hud.title)
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .tracking(0.6)
                    .foregroundStyle(Brand.muted)
                Text(hud.value)
                    .font(.title3.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Brand.text)
                    .contentTransition(.numericText())
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 22)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Brand.border))
        .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
        .accessibilityElement(children: .combine)
    }
}
