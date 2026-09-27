import SwiftUI

/// How a `CaptureLevelBand` reads to the operator. The band itself is decided
/// by groove-detector; this is only its wording and colour.
extension CaptureLevelBand {
    var title: String {
        switch self {
        case .unknown: return "Measuring"
        case .tooLow: return "Too low"
        case .low: return "Low"
        case .good: return "Good"
        case .high: return "High"
        case .clipping: return "Clipping"
        }
    }

    var guidance: String {
        switch self {
        case .unknown: return "Keep the music playing — Oceano needs a few seconds of it to judge the level."
        case .tooLow: return "Raise the input gain. Quiet passages will be missed at this level."
        case .low: return "Raise the input gain a little more."
        case .good: return "This level is right for recognition."
        case .high: return "Lower the input gain a step — loud passages are close to distorting."
        case .clipping: return "Lower the input gain — the signal is distorting."
        }
    }

    var color: Color {
        switch self {
        case .unknown: return Brand.muted
        case .tooLow, .clipping: return Brand.err
        case .low, .high: return Brand.warn
        case .good: return Brand.ok
        }
    }
}

/// Maps a 0–1 full-scale RMS onto a meter track in dBFS, so a level ten
/// times quieter moves the needle by a fixed distance rather than vanishing
/// at the left edge.
struct LevelMeterScale {
    var floorDB: Double = -40

    func position(forRMS rms: Double) -> Double {
        guard rms > 0 else { return 0 }
        let db = 20 * log10(rms)
        return min(max((db - floorDB) / -floorDB, 0), 1)
    }
}

/// A horizontal meter: coloured zones from the detector's band edges and a
/// needle at the current programme level.
struct LevelMeterView: View {
    let programme: ProgrammeLevel
    var scale = LevelMeterScale()

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let t = programme.target
            let tooLow = scale.position(forRMS: t.tooLowBelow)
            let low = scale.position(forRMS: t.lowBelow)
            let high = scale.position(forRMS: t.highAbove)
            ZStack(alignment: .leading) {
                HStack(spacing: 0) {
                    zone(Brand.err, width: w * tooLow)
                    zone(Brand.warn, width: w * (low - tooLow))
                    zone(Brand.ok, width: w * (high - low))
                    zone(Brand.warn, width: w * (1 - high))
                }
                .clipShape(Capsule())
                if programme.band != .unknown {
                    Capsule()
                        .fill(Brand.text)
                        .frame(width: 4, height: 22)
                        .offset(x: max(0, w * scale.position(forRMS: programme.rmsP95) - 2))
                        .animation(.easeOut(duration: 0.4), value: programme.rmsP95)
                }
            }
            .frame(height: 22)
        }
        .frame(height: 22)
        .accessibilityElement()
        .accessibilityLabel("Input level")
        .accessibilityValue(programme.band.title)
    }

    private func zone(_ color: Color, width: Double) -> some View {
        color.opacity(0.35).frame(width: max(0, width), height: 12)
    }
}
