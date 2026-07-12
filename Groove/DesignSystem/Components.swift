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
