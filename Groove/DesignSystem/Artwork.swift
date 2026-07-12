import SwiftUI

/// Square artwork with a graceful vinyl-record placeholder and loading shimmer.
/// Resolves relative catalog paths against the configured server.
struct Artwork: View {
    let raw: String?
    var cornerRadius: CGFloat = 10

    @Environment(AppSettings.self) private var settings

    var body: some View {
        let url = settings.resolveArtwork(raw)
        return AsyncImage(url: url, transaction: .init(animation: .easeInOut(duration: 0.25))) { phase in
            switch phase {
            case let .success(image):
                image.resizable().scaledToFill()
            case .failure:
                placeholder
            case .empty:
                if url == nil { placeholder } else { shimmer }
            @unknown default:
                placeholder
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Brand.border, lineWidth: 1)
        )
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(
                colors: [Brand.cardElevated, Brand.card],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            Image(systemName: "opticaldisc")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(Brand.muted.opacity(0.5))
        }
    }

    private var shimmer: some View {
        Brand.cardElevated.overlay(
            ProgressView().tint(Brand.muted).controlSize(.small)
        )
    }
}
