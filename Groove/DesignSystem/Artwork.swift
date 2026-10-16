import SwiftUI

/// Artwork in a square slot with a graceful vinyl-record placeholder and
/// loading shimmer. Resolves relative catalog paths against the configured
/// server. A cover clearly off square (a cassette J-card) is drawn whole in
/// its own proportions, fitted and centred in the slot, instead of being
/// cropped to a square; the slot itself never grows.
struct Artwork: View {
    let raw: String?
    var cornerRadius: CGFloat = 10
    /// VoiceOver label. When nil the artwork is treated as decorative and hidden
    /// from assistive tech (the accompanying text carries the meaning).
    var label: String? = nil
    /// Shows a spinning-disc placeholder instead of the static one — audio is
    /// playing but not yet identified, distinct from "no artwork at all."
    var isRecognizing: Bool = false

    /// How far from 1:1 a cover may be and still fill the square (cropping the
    /// difference). Same rule as groove-display and the catalog Studio: CD and
    /// LP scans are rarely exactly square, a cassette J-card is ~0.63.
    static let squareTolerance: CGFloat = 1.1

    @Environment(AppSettings.self) private var settings
    @State private var loaded: (url: URL, image: UIImage)?
    @State private var failed = false
    // A single transient blip fetching an external cover-art CDN over the
    // LAN would otherwise leave the placeholder up for good, so a failed
    // load is retried a couple of times before settling on the placeholder.
    @State private var retryCount = 0
    private let maxRetries = 2

    var body: some View {
        let url = settings.resolveArtwork(raw)
        // The slot is the largest square inside the proposal: a tall cover can
        // never stretch it, and a caller proposing a taller-than-wide area
        // (e.g. `.frame(maxWidth:)` under `.aspectRatio(1)` in a scroll view)
        // still gets a square, not a cropped portrait rectangle.
        return Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay { content(for: url) }
            .task(id: LoadKey(url: url, attempt: retryCount)) { await load(url) }
            .accessibilityLabel(label ?? "")
            .accessibilityHidden(label == nil)
    }

    @ViewBuilder
    private func content(for url: URL?) -> some View {
        if let loaded, loaded.url == url {
            let size = loaded.image.size
            let aspect = size.height > 0 ? size.width / size.height : 1
            if aspect > 1 / Self.squareTolerance && aspect < Self.squareTolerance {
                framed(Color.clear.overlay {
                    Image(uiImage: loaded.image).resizable().scaledToFill()
                })
            } else {
                framed(Image(uiImage: loaded.image).resizable())
                    .aspectRatio(aspect, contentMode: .fit)
            }
        } else if url == nil || failed {
            framed(placeholder)
        } else {
            framed(shimmer)
        }
    }

    private func framed(_ view: some View) -> some View {
        view
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Brand.border, lineWidth: 1)
            )
    }

    private struct LoadKey: Equatable {
        let url: URL?
        let attempt: Int
    }

    private func load(_ url: URL?) async {
        guard let url else { return }
        if loaded?.url == url { return }
        failed = false
        if retryCount > 0 {
            try? await Task.sleep(for: .milliseconds(600 * Int64(retryCount)))
            guard !Task.isCancelled else { return }
        }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard !Task.isCancelled else { return }
            guard (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true,
                  let image = UIImage(data: data) else { throw URLError(.cannotDecodeContentData) }
            withAnimation(.easeInOut(duration: 0.25)) { loaded = (url, image) }
        } catch {
            guard !Task.isCancelled else { return }
            if retryCount < maxRetries {
                retryCount += 1
            } else {
                failed = true
            }
        }
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
