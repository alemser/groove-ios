import SwiftUI

/// Playback summary pinned above the tab bar on Home — a stream or a
/// record (`NowPlayingModel.summary`). Tapping it opens `NowPlayingView`.
struct NowPlayingMiniBar: View {
    @Environment(NowPlayingModel.self) private var nowPlaying
    @Environment(NavigationState.self) private var navigation

    var body: some View {
        if let s = nowPlaying.summary {
            Button {
                navigation.openNowPlaying()
            } label: {
                HStack(spacing: 10) {
                    Artwork(raw: s.artworkUrl, cornerRadius: 8, isRecognizing: s.isRecognizing)
                        .frame(width: 40, height: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Brand.text)
                            .lineLimit(1)
                        Text(s.subtitle)
                            .font(.caption)
                            .foregroundStyle(Brand.muted)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.up")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Brand.muted)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Brand.border, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open Now Playing")
            .accessibilityValue("\(s.title), \(s.subtitle)")
        }
    }
}
