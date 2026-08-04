import SwiftUI

/// Landing tab: connection health, a live Now Playing summary, and quick access
/// to what needs attention — the dashboard `groove-ios` didn't have before, in
/// the spirit of `oceano-player-ios`'s Home.
struct HomeView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(AttentionCenter.self) private var attention
    @Environment(NavigationState.self) private var navigation
    @Environment(NowPlayingModel.self) private var nowPlaying

    var body: some View {
        NavigationStack {
            List {
                connectionSection
                nowPlayingSection
                if attention.count > 0 {
                    attentionSection
                }
                quickLinksSection
            }
            .scrollContentBackground(.hidden)
            .grooveScreenBackground()
            .navigationTitle("Groove")
        }
    }

    // MARK: - Connection

    private var connectionSection: some View {
        Section("Connection") {
            if nowPlaying.hasLoadedOnce, nowPlaying.errorMessage == nil {
                Label("Connected to \(settings.host)", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Brand.ok)
            } else if let error = nowPlaying.errorMessage {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Connection issue", systemImage: "wifi.exclamationmark")
                        .foregroundStyle(Brand.warn)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(Brand.muted)
                }
            } else {
                Label("Connecting…", systemImage: "hourglass")
                    .foregroundStyle(Brand.muted)
            }
        }
    }

    // MARK: - Now Playing

    private var nowPlayingSection: some View {
        Section("Now Playing") {
            Button {
                navigation.openNowPlaying()
            } label: {
                if let pb = nowPlaying.status?.playback, pb.active {
                    HStack(spacing: 12) {
                        Artwork(raw: pb.artworkUrl, cornerRadius: 8)
                            .frame(width: 48, height: 48)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(pb.title?.nonEmpty ?? "Now Playing")
                                .font(.headline)
                                .foregroundStyle(Brand.text)
                                .lineLimit(1)
                            Text(pb.artist?.nonEmpty ?? "Unknown artist")
                                .font(.subheadline)
                                .foregroundStyle(Brand.muted)
                                .lineLimit(1)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Brand.muted)
                    }
                } else {
                    Label("Nothing playing", systemImage: "opticaldisc")
                        .foregroundStyle(Brand.muted)
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the full Now Playing screen")
        }
    }

    // MARK: - Attention

    private var attentionSection: some View {
        Section {
            Button {
                navigation.selectedTab = .review
            } label: {
                HStack {
                    Label(
                        "\(attention.count) item\(attention.count == 1 ? "" : "s") need review",
                        systemImage: "checkmark.seal"
                    )
                    .foregroundStyle(Brand.text)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Brand.muted)
                }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Quick links

    private var quickLinksSection: some View {
        Section("Quick Links") {
            quickLink(title: "Library", subtitle: "Browse releases and tracks", icon: "square.stack") {
                navigation.selectedTab = .library
            }
            quickLink(title: "History", subtitle: "Recent recognitions", icon: "clock.arrow.circlepath") {
                navigation.selectedTab = .history
            }
            quickLink(title: "Rig", subtitle: "Catalog server, stylus, enrichers, health", icon: "hifispeaker.and.homepod") {
                navigation.selectedTab = .rig
            }
        }
    }

    private func quickLink(title: String, subtitle: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .foregroundStyle(Brand.accent)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundStyle(Brand.text)
                    Text(subtitle).font(.caption).foregroundStyle(Brand.muted)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Brand.muted)
            }
        }
        .buttonStyle(.plain)
    }
}
