import SwiftUI

/// Native vector marks for vinyl/CD — drawn with `Canvas` (not image assets)
/// so they stay crisp and legible at any size and tint cleanly via `color`.
/// Vinyl gets a tonearm resting perpendicular over the disc (the cue that
/// actually reads as "record player" — a plain ringed circle alone is
/// indistinguishable from a CD); CD stays a plain disc with a center hole.
enum MediaFormatIcon {
    enum Kind { case vinyl, cd }

    /// Maps a raw `release_format`/`media_format` value (`vinyl`, `cd`, …) to
    /// its mark. Returns nil for formats with no dedicated icon (cassette,
    /// digital, …) so callers can fall back to a text badge.
    static func kind(for raw: String?) -> Kind? {
        guard let raw = raw?.nonEmpty else { return nil }
        switch raw.lowercased() {
        case "vinyl": return .vinyl
        case "cd": return .cd
        default: return nil
        }
    }

    static func mark(_ kind: Kind, size: CGFloat, color: Color) -> some View {
        Canvas { context, canvasSize in
            let w = canvasSize.width
            let cx = w / 2
            let cy = canvasSize.height / 2
            let radius = min(w, canvasSize.height) * 0.42

            func strokeCircle(_ r: CGFloat, lineWidth: CGFloat, opacity: Double = 1) {
                let rect = CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)
                context.stroke(Path(ellipseIn: rect), with: .color(color.opacity(opacity)), lineWidth: lineWidth)
            }
            func fillCircle(at point: CGPoint, r: CGFloat) {
                let rect = CGRect(x: point.x - r, y: point.y - r, width: r * 2, height: r * 2)
                context.fill(Path(ellipseIn: rect), with: .color(color))
            }

            switch kind {
            case .vinyl:
                strokeCircle(radius, lineWidth: max(1, w * 0.09))
                strokeCircle(radius * 0.62, lineWidth: max(0.6, w * 0.035), opacity: 0.4)
                fillCircle(at: CGPoint(x: cx, y: cy), r: radius * 0.22)

                // Tonearm resting near-perpendicular over the disc, stylus tip toward center.
                let armTop = CGPoint(x: w * 0.72, y: canvasSize.height * 0.05)
                let armTip = CGPoint(x: w * 0.52, y: canvasSize.height * 0.52)
                var arm = Path()
                arm.move(to: armTop)
                arm.addLine(to: armTip)
                context.stroke(arm, with: .color(color), style: StrokeStyle(lineWidth: max(1, w * 0.11), lineCap: .round))
                fillCircle(at: armTip, r: w * 0.07)

            case .cd:
                strokeCircle(radius, lineWidth: max(1, w * 0.09))
                strokeCircle(radius * 0.5, lineWidth: max(0.6, w * 0.035), opacity: 0.4)
                strokeCircle(radius * 0.16, lineWidth: max(1, w * 0.08))
            }
        }
        .frame(width: size, height: size)
    }
}
