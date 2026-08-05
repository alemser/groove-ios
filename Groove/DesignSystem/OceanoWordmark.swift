import SwiftUI

/// "Ocean" + a colorful vinyl-record mark standing in for the final "o" —
/// echoes the app icon's own disc/label/spindle design (teal ring, gold
/// label) rather than the thin turntable-and-tonearm glyph used inline
/// elsewhere, which reads as a stray shape rather than a round "o" at
/// wordmark size. Parity in spirit (not pixel) with groove-catalog's studio
/// wordmark (`static/studio-brand.js`: "Ocean" + a vinyl mark as the final `O`).
struct OceanoWordmark: View {
    var fontSize: CGFloat = 34
    var weight: Font.Weight = .bold
    var color: Color = Brand.text

    var body: some View {
        HStack(spacing: fontSize * 0.06) {
            Text("Ocean")
                .font(.system(size: fontSize, weight: weight))
                .foregroundStyle(color)
            VinylRecordMark(size: fontSize * 0.94)
                .offset(y: fontSize * 0.03)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Oceano")
    }
}

/// Colorful vinyl-record mark (teal ring, dark grooves, gold label, spindle
/// hole) matching `AppIcon.appiconset/icon-1024.png`, drawn natively so it
/// stays crisp at any size instead of depending on an image asset.
struct VinylRecordMark: View {
    var size: CGFloat
    var ringColor: Color = Brand.teal
    var labelColor: Color = Brand.gold
    var holeColor: Color = Brand.bg

    var body: some View {
        ZStack {
            Circle().fill(Brand.card)
            ForEach([0.78, 0.62, 0.46], id: \.self) { ratio in
                Circle()
                    .stroke(ringColor.opacity(0.3), lineWidth: max(0.5, size * 0.012))
                    .frame(width: size * ratio, height: size * ratio)
            }
            Circle().stroke(ringColor, lineWidth: max(1, size * 0.08))
            Circle().fill(labelColor).frame(width: size * 0.42, height: size * 0.42)
            Circle().fill(holeColor).frame(width: size * 0.1, height: size * 0.1)
        }
        .frame(width: size, height: size)
    }
}
