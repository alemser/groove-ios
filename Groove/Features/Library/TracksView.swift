import SwiftUI

struct TracksView: View {
    @Environment(AppSettings.self) private var settings
    @State private var model = TracksModel()
    @State private var search = ""

    var body: some View {
        content
            .task { model.configure(settings) }
    }

    private var filtered: [Track] {
        guard !search.isEmpty else { return model.tracks }
        let q = search.lowercased()
        return model.tracks.filter {
            ($0.title ?? "").lowercased().contains(q) ||
            ($0.artist ?? "").lowercased().contains(q) ||
            ($0.album ?? "").lowercased().contains(q)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loading:
            LoadingView()
        case let .error(message):
            ErrorStateView(message: message) { Task { await model.reload() } }
        case .loaded:
            if model.tracks.isEmpty {
                EmptyStateView(icon: "music.note.list", title: "No tracks", message: "Identified tracks land in your catalog automatically.")
            } else {
                list
            }
        }
    }

    private var list: some View {
        List {
            ForEach(filtered) { track in
                NavigationLink(value: track.id) {
                    TrackRowView(track: track)
                }
                .listRowBackground(Brand.surface)
                .listRowSeparatorTint(Brand.border)
                .task { await model.loadMoreIfNeeded(current: track) }
            }
            if model.canLoadMore && search.isEmpty {
                HStack { Spacer(); ProgressView().tint(Brand.muted); Spacer() }
                    .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Filter loaded tracks")
        .refreshable { await model.reload() }
    }
}

struct TrackRowView: View {
    let track: Track

    var body: some View {
        HStack(spacing: 12) {
            Artwork(raw: "/catalog/artwork/tracks/\(track.id)")
                .frame(width: 50, height: 50)
            VStack(alignment: .leading, spacing: 3) {
                Text(track.displayTitle)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Brand.text)
                    .lineLimit(1)
                Text(track.displayArtist)
                    .font(.subheadline)
                    .foregroundStyle(Brand.muted)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if track.hasDisplayOverride == true {
                        Badge(text: "Edited", color: Brand.teal)
                    }
                    if track.releaseConfirmed == true {
                        Badge(text: "Confirmed", color: Brand.gold)
                    }
                    if let media = Format.mediaFormat(track.releaseFormat) {
                        Text(media).font(.caption2).foregroundStyle(Brand.muted)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(track.displayTitle), \(track.displayArtist)")
    }
}
