import SwiftUI

struct PlaysView: View {
    @Environment(AppSettings.self) private var settings
    @State private var model = PlaysModel()

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("History")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Toggle("Show unidentified", isOn: Binding(
                                get: { model.includeFailed },
                                set: { model.includeFailed = $0 }
                            ))
                        } label: {
                            Image(systemName: model.includeFailed ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                        }
                        .accessibilityLabel("Filter history")
                    }
                }
                .grooveScreenBackground()
        }
        .task { model.configure(settings) }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loading:
            LoadingView()
        case let .error(message):
            ErrorStateView(message: message) { Task { await model.reload() } }
        case .loaded:
            if model.plays.isEmpty {
                EmptyStateView(icon: "clock", title: "No plays yet", message: "Identified tracks will show up here.")
            } else {
                list
            }
        }
    }

    private var list: some View {
        List {
            ForEach(model.plays) { play in
                Group {
                    if let trackId = play.trackId {
                        NavigationLink(value: trackId) { PlayRowView(play: play) }
                    } else {
                        PlayRowView(play: play)
                    }
                }
                .listRowBackground(Brand.surface)
                .listRowSeparatorTint(Brand.border)
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        Task { await model.delete(play) }
                    } label: { Label("Delete", systemImage: "trash") }
                }
                .task { await model.loadMoreIfNeeded(current: play) }
            }
            if model.canLoadMore {
                HStack { Spacer(); ProgressView().tint(Brand.muted); Spacer() }
                    .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .refreshable { await model.reload() }
        .navigationDestination(for: Int64.self) { trackId in
            TrackDetailView(trackId: trackId)
        }
    }
}

struct PlayRowView: View {
    let play: Play

    var body: some View {
        HStack(spacing: 12) {
            Artwork(raw: play.artworkUrl)
                .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 3) {
                Text(play.displayTitle)
                    .font(.body.weight(.medium))
                    .foregroundStyle(play.isIdentified ? Brand.text : Brand.muted)
                    .lineLimit(1)
                Text(play.displayArtist)
                    .font(.subheadline)
                    .foregroundStyle(Brand.muted)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if let source = play.source?.nonEmpty, play.isIdentified {
                        Badge(text: SourceStyle.label(for: source), color: SourceStyle.color(for: source))
                    }
                    if play.releaseConfirmed == true {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.caption2)
                            .foregroundStyle(Brand.gold)
                    }
                    if let media = Format.mediaFormat(play.releaseFormat) {
                        Text(media).font(.caption2).foregroundStyle(Brand.muted)
                    }
                }
            }
            Spacer(minLength: 4)
            Text(Format.relative(play.startedAt))
                .font(.caption)
                .foregroundStyle(Brand.muted)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(play.displayTitle), \(play.displayArtist), \(Format.relative(play.startedAt))")
    }
}
