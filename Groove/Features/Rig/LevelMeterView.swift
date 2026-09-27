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

/// A horizontal meter over coloured zones (from the detector's band edges):
///
/// - a white needle for the live level, which follows the music;
/// - a marker under the track for the level the verdict is based on
///   (the window's P95), in the band's colour;
/// - an outlined marker for where a pending gain step will put that level.
struct LevelMeterView: View {
    let programme: ProgrammeLevel
    var previewRMS: Double?
    var scale = LevelMeterScale()

    private let trackHeight: CGFloat = 12
    private let height: CGFloat = 34

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let t = programme.target
            let tooLow = scale.position(forRMS: t.tooLowBelow)
            let low = scale.position(forRMS: t.lowBelow)
            let high = scale.position(forRMS: t.highAbove)
            ZStack(alignment: .topLeading) {
                HStack(spacing: 0) {
                    zone(Brand.err, width: w * tooLow)
                    zone(Brand.warn, width: w * (low - tooLow))
                    zone(Brand.ok, width: w * (high - low))
                    zone(Brand.warn, width: w * (1 - high))
                }
                .clipShape(Capsule())
                .offset(y: 5)

                if let preview = previewRMS {
                    Capsule()
                        .stroke(Brand.teal, lineWidth: 2)
                        .frame(width: 8, height: 22)
                        .offset(x: x(preview, in: w) - 4)
                        .animation(.easeOut(duration: 0.15), value: preview)
                }

                Capsule()
                    .fill(Brand.text)
                    .frame(width: 3, height: 22)
                    .offset(x: x(programme.liveRms, in: w) - 1.5)
                    .animation(.linear(duration: 0.25), value: programme.liveRms)

                if programme.band != .unknown {
                    Image(systemName: "arrowtriangle.up.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(programme.band.color)
                        .offset(x: x(programme.rmsP95, in: w) - 5, y: 23)
                        .animation(.easeOut(duration: 0.4), value: programme.rmsP95)
                }
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityLabel("Input level")
        .accessibilityValue(programme.band.title)
    }

    private func x(_ rms: Double, in width: Double) -> Double {
        width * scale.position(forRMS: rms)
    }

    private func zone(_ color: Color, width: Double) -> some View {
        color.opacity(0.35).frame(width: max(0, width), height: trackHeight)
    }
}
