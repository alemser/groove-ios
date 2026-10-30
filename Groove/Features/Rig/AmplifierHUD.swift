import Foundation

/// One change the amplifier reported about itself, shown briefly over the
/// remote: the volume the amp actually landed on, the tone step, the input,
/// standby. Read from the amp's state provider, so it also shows changes
/// made with the amp's own remote or front panel.
struct AmplifierHUD: Equatable {
    var symbol: String
    var title: String
    var value: String

    /// What changed from `old` to `new`, or nil when nothing shown here did.
    /// A field the provider stops knowing (nil) is not a change. When one
    /// event changes several fields, the first in this order is shown:
    /// power, input, volume, bass, treble, balance, loudness, speakers —
    /// switching on or changing input redraws the volume too, and the cause
    /// is what the listener did.
    static func change(
        from old: RigAmplifierReading,
        to new: RigAmplifierReading,
        inputLabel: (String) -> String
    ) -> AmplifierHUD? {
        if let p = new.power, p != old.power {
            return AmplifierHUD(symbol: "power", title: "Amplifier", value: p == .on ? "On" : "Standby")
        }
        if let id = new.inputId, id != old.inputId {
            return AmplifierHUD(symbol: "cable.connector", title: "Input", value: inputLabel(id))
        }
        if let v = new.volumeDb, v != old.volumeDb {
            return AmplifierHUD(symbol: "speaker.wave.2.fill", title: "Volume", value: decibels(v))
        }
        if let v = new.bassDb, v != old.bassDb {
            return AmplifierHUD(symbol: "dial.low", title: "Bass", value: decibels(v, signed: true))
        }
        if let v = new.trebleDb, v != old.trebleDb {
            return AmplifierHUD(symbol: "dial.high", title: "Treble", value: decibels(v, signed: true))
        }
        if let b = new.balance, b != old.balance {
            return AmplifierHUD(symbol: "arrow.left.and.right", title: "Balance", value: balance(b))
        }
        if let on = new.loudness, on != old.loudness {
            return AmplifierHUD(symbol: "waveform", title: "Loudness", value: on ? "On" : "Off")
        }
        if let on = new.speakers, on != old.speakers {
            return AmplifierHUD(symbol: "hifispeaker.2", title: "Speakers", value: on ? "On" : "Off")
        }
        return nil
    }

    /// "−22.5 dB", "−28.75 dB", "0 dB"; signed adds "+" above 0 ("+2 dB"),
    /// the way tone controls read. A true minus sign, not a hyphen.
    static func decibels(_ v: Double, signed: Bool = false) -> String {
        let magnitude = abs(v).formatted(.number.precision(.fractionLength(0...2)))
        let sign = v < 0 ? "\u{2212}" : (signed && v > 0 ? "+" : "")
        return "\(sign)\(magnitude) dB"
    }

    /// "Centre", or the attenuation and which channel the balance favours
    /// ("−5 dB, left"); just the dB when the provider can't tell the side.
    static func balance(_ b: RigAmplifierBalance) -> String {
        guard b.db != 0 else { return "Centre" }
        switch b.side {
        case .left: return "\(decibels(b.db)), left"
        case .right: return "\(decibels(b.db)), right"
        case nil: return decibels(b.db)
        }
    }
}
