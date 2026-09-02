import SwiftUI

/// Square artwork with a graceful vinyl-record placeholder and loading shimmer.
/// Resolves relative catalog paths against the configured server.
struct Artwork: View {
    let raw: String?
    var cornerRadius: CGFloat = 10
    /// VoiceOver label. When nil the artwork is treated as decorative and hidden
    /// from assistive tech (the accompanying text carries the meaning).
    var label: String? = nil
    /// Shows a spinning-disc placeholder instead of the static one — audio is
    /// playing but not yet identified, distinct from "no artwork at all."
    var isRecognizing: Bool = false

    @Environment(AppSettings.self) private var settings
    // AsyncImage never retries on its own — a single transient blip fetching
    // an external cover-art CDN over the LAN (the common case here, unlike
    // the web UI's browser-level retry/caching) leaves the placeholder up
    // for good. Bumping this forces AsyncImage to recreate itself and try
    // again, up to a couple of times, before settling on the placeholder.
    @State private var retryCount = 0
    private let maxRetries = 2

    var body: some View {
        let url = settings.resolveArtwork(raw)
        return AsyncImage(url: url, transaction: .init(animation: .easeInOut(duration: 0.25))) { phase in
            switch phase {
            case let .success(image):
                image.resizable().scaledToFill()
            case .failure:
                placeholder
                    .task(id: retryCount) {
                        guard retryCount < maxRetries else { return }
                        try? await Task.sleep(for: .milliseconds(600 * Int64(retryCount + 1)))
                        guard !Task.isCancelled else { return }
                        retryCount += 1
                    }
            case .empty:
                if url == nil { placeholder } else { shimmer }
            @unknown default:
                placeholder
            }
        }
        .id(retryCount)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Brand.border, lineWidth: 1)
        )
        .accessibilityLabel(label ?? "")
        .accessibilityHidden(label == nil)
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(
                colors: [Brand.cardElevated, Brand.card],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            if isRecognizing {
                SpinningDiscGlyph()
            } else {
                Image(systemName: "opticaldisc")
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(Brand.muted.opacity(0.5))
            }
        }
    }

    private var shimmer: some View {
        Brand.cardElevated.overlay(
            ProgressView().tint(Brand.muted).controlSize(.small)
        )
    }
}

/// Continuously-rotating disc glyph — "actively working," not stalled or broken.
/// Runs off `onAppear`, so it restarts cleanly whenever `Artwork` is re-created
/// (e.g. a fresh AsyncImage identity), which is fine: a spinning record doesn't
/// need a stable rotation phase across those recreations.
private struct SpinningDiscGlyph: View {
    @State private var rotation: Double = 0

    var body: some View {
        Image(systemName: "opticaldisc")
            .font(.system(size: 26, weight: .light))
            .foregroundStyle(Brand.muted.opacity(0.7))
            .rotationEffect(.degrees(rotation))
            .onAppear {
                withAnimation(.linear(duration: 2.2).repeatForever(autoreverses: false)) {
                    rotation = 360
                }
            }
    }
}
