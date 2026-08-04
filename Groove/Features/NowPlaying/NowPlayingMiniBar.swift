import SwiftUI

/// Persistent playback summary pinned above the tab bar, visible on every tab.
/// Tapping it opens the full `NowPlayingView` as a sheet — mirrors Apple Music's
/// mini-player so "what's playing" never requires leaving the current tab.
struct NowPlayingMiniBar: View {
    @Environment(NowPlayingModel.self) private var nowPlaying
    @Environment(NavigationState.self) private var navigation

    /// Caller (`MainTabView`) only shows this when `playback.active`; this view
    /// trusts that gate rather than re-checking it.
    var body: some View {
        if let pb = nowPlaying.status?.playback {
            Button {
                navigation.openNowPlaying()
            } label: {
                HStack(spacing: 10) {
                    Artwork(raw: pb.artworkUrl, cornerRadius: 8)
                        .frame(width: 40, height: 40)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(pb.title?.nonEmpty ?? "Now Playing")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Brand.text)
                            .lineLimit(1)
                        Text(pb.artist?.nonEmpty ?? "Unknown artist")
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
            .accessibilityValue("\(pb.title?.nonEmpty ?? "Now playing"), \(pb.artist?.nonEmpty ?? "unknown artist")")
        }
    }
}
