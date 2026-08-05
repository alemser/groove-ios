import SwiftUI

// MARK: - Badge

/// Small pill used for source, status, and format tags.
struct Badge: View {
    let text: String
    var color: Color = Brand.muted
    var filled = false

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .textCase(.uppercase)
            .tracking(0.4)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(filled ? Brand.bg : color)
            .background(filled ? color : color.opacity(0.14))
            .clipShape(Capsule())
    }
}

/// Same pill as `Badge`, but for a release/media format it shows the
/// vinyl/CD vector mark instead of (or alongside, when `labeled`) the word —
/// falls back to the plain text badge for formats with no dedicated icon
/// (cassette, digital, …).
struct MediaFormatBadge: View {
    let raw: String?
    var color: Color = Brand.gold
    /// Icon-only by default (compact contexts: grids, lists). Set true on
    /// screens with room to spare — e.g. Now Playing — so the format reads
    /// at a glance instead of relying on the glyph alone.
    var labeled = false

    var body: some View {
        if let text = Format.mediaFormat(raw) {
            if let kind = MediaFormatIcon.kind(for: raw) {
                HStack(spacing: 5) {
                    MediaFormatIcon.mark(kind, size: 16, color: color)
                    if labeled {
                        Text(text)
                            .font(.caption2.weight(.semibold))
                            .textCase(.uppercase)
                            .tracking(0.4)
                            .foregroundStyle(color)
                    }
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(color.opacity(0.14))
                .clipShape(Capsule())
                .accessibilityLabel(text)
            } else {
                Badge(text: text, color: color)
            }
        }
    }
}

// MARK: - Section label

struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.footnote.weight(.semibold))
            .textCase(.uppercase)
            .tracking(0.6)
            .foregroundStyle(Brand.muted)
    }
}

// MARK: - Key/value row

struct InfoRow: View {
    let label: String
    let value: String
    var mono = false

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(Brand.muted)
            Spacer(minLength: 12)
            Text(value)
                .font(mono ? .subheadline.monospaced() : .subheadline)
                .foregroundStyle(Brand.text)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }
}

// MARK: - Tracklist row

/// Position / title / duration row shared by the release-candidate card
/// (Review flow) and the confirmed album detail screen (Library flow).
struct TracklistEntryRow: View {
    let entry: TracklistEntry
    var compact = true
    /// True when this is the track currently playing on the rig — swaps the
    /// position number for a waveform glyph and tints the title, mirroring
    /// oceano-player-ios's album tracklist.
    var isPlaying = false

    var body: some View {
        HStack {
            if isPlaying {
                Image(systemName: "waveform")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Brand.teal)
                    .frame(width: 28, alignment: .leading)
                    .symbolEffect(.variableColor.iterative, options: .repeating)
            } else {
                Text(entry.position ?? "\(entry.ordinal)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Brand.muted)
                    .frame(width: 28, alignment: .leading)
            }
            Text(entry.title?.nonEmpty ?? "—")
                .font(compact ? .caption : .callout)
                .fontWeight(isPlaying ? .semibold : .regular)
                .foregroundStyle(isPlaying ? Brand.teal : Brand.text)
                .lineLimit(1)
            Spacer()
            Text(Format.duration(entry.durationMs))
                .font(.caption.monospacedDigit())
                .foregroundStyle(Brand.muted)
        }
    }
}

// MARK: - State views

struct LoadingView: View {
    var label = "Loading…"
    var body: some View {
        VStack(spacing: 12) {
            ProgressView().tint(Brand.accent)
            Text(label).font(.subheadline).foregroundStyle(Brand.muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: String
    var message: String? = nil

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: icon)
        } description: {
            if let message { Text(message) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ErrorStateView: View {
    let message: String
    var retry: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 34))
                .foregroundStyle(Brand.warn)
            Text("Something went wrong")
                .font(.headline)
                .foregroundStyle(Brand.text)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Brand.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            if let retry {
                Button("Try Again", action: retry)
                    .buttonStyle(.borderedProminent)
                    .tint(Brand.accent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Source / status coloring shared across features

enum SourceStyle {
    static func color(for source: String) -> Color {
        switch source.lowercased() {
        case "acrcloud", "audd": return Brand.teal
        case "local_index", "local": return Brand.gold
        case "album_programme", "programme_hold": return Brand.warn
        case "manual", "user": return Brand.ok
        default: return Brand.muted
        }
    }

    static func label(for source: String) -> String {
        switch source.lowercased() {
        case "local_index": return "Local"
        case "album_programme": return "Programme"
        case "programme_hold": return "Hold"
        default: return source.replacingOccurrences(of: "_", with: " ")
        }
    }
}
