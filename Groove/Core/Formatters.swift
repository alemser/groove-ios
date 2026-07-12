import Foundation

enum Format {
    /// Milliseconds → `m:ss` (or `h:mm:ss`).
    static func duration(_ ms: Int64?) -> String {
        guard let ms, ms > 0 else { return "—" }
        let totalSeconds = Int(ms / 1000)
        let s = totalSeconds % 60
        let m = (totalSeconds / 60) % 60
        let h = totalSeconds / 3600
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func date(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        return iso.date(from: raw) ?? isoPlain.date(from: raw)
    }

    /// Relative "2h ago" style string for a wire timestamp.
    static func relative(_ raw: String?) -> String {
        guard let date = date(raw) else { return "" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    /// Absolute "Jul 12, 2026 at 3:14 PM" style for detail rows.
    static func absolute(_ raw: String?) -> String {
        guard let date = date(raw) else { return "—" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    static func confidence(_ value: Double?) -> String? {
        guard let value, value > 0 else { return nil }
        return "\(Int((value * 100).rounded()))%"
    }

    static func mediaFormat(_ raw: String?) -> String? {
        guard let raw = raw?.nonEmpty else { return nil }
        switch raw.lowercased() {
        case "vinyl": return "Vinyl"
        case "cd": return "CD"
        case "digital": return "Digital"
        case "cassette": return "Cassette"
        default: return raw.capitalized
        }
    }
}
