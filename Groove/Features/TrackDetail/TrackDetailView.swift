import SwiftUI

struct TrackDetailView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @State private var model: TrackDetailModel
    @State private var editing = false
    @State private var showDeleteConfirm = false
    @State private var showChangeRelease = false
    @State private var rejectTarget: Play?
    @State private var identifyTarget: Play?

    init(trackId: Int64) {
        _model = State(initialValue: TrackDetailModel(trackId: trackId))
    }

    var body: some View {
        content
            .grooveScreenBackground()
            .navigationTitle("Track")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if model.track != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button { editing = true } label: { Label("Edit Names", systemImage: "pencil") }
                            if model.track?.hasDisplayOverride == true {
                                Button { Task { await model.resetOverrides() } } label: {
                                    Label("Reset to Provider", systemImage: "arrow.uturn.backward")
                                }
                            }
                            Button { showChangeRelease = true } label: {
                                Label("Change Release", systemImage: "arrow.triangle.2.circlepath")
                            }
                            Divider()
                            Button(role: .destructive) { showDeleteConfirm = true } label: {
                                Label("Delete Track", systemImage: "trash")
                            }
                        } label: { Image(systemName: "ellipsis.circle") }
                        .accessibilityLabel("Track actions")
                    }
                }
            }
            .task { model.configure(settings) }
            .sheet(isPresented: $editing) {
                if let track = model.track {
                    EditTrackView(track: track) { patch in
                        await model.save(patch)
                    }
                }
            }
            .sheet(isPresented: $showChangeRelease) {
                if let track = model.track {
                    ChangeReleaseSheet(
                        trackId: track.id,
                        seedArtist: track.displayArtist,
                        seedTitle: track.displayTitle,
                        seedAlbum: track.displayAlbum
                    ) { Task { await model.load() } }
                }
            }
            .confirmationDialog("Delete this track from the catalog?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    Task { if await model.delete() { dismiss() } }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Plays are detached and enrich jobs cleaned up. This can't be undone.")
            }
            .confirmationDialog(
                "This isn't the right song?",
                isPresented: Binding(get: { rejectTarget != nil }, set: { if !$0 { rejectTarget = nil } }),
                titleVisibility: .visible
            ) {
                Button("Search for the Correct Song") {
                    identifyTarget = rejectTarget
                    rejectTarget = nil
                }
                Button("Remove This Play", role: .destructive) {
                    if let play = rejectTarget { Task { await model.rejectPlay(epoch: play.listenerEpoch) } }
                    rejectTarget = nil
                }
                Button("Cancel", role: .cancel) { rejectTarget = nil }
            } message: {
                Text("Reject this recognition — either point it at the right song, or just remove the play.")
            }
            .sheet(item: $identifyTarget) { play in
                ManualIdentifySheet(
                    epoch: play.listenerEpoch,
                    seedArtist: play.artist,
                    seedTitle: play.title,
                    seedAlbum: play.album
                ) { Task { await model.load() } }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loading:
            LoadingView()
        case let .error(message):
            ErrorStateView(message: message) { Task { await model.load() } }
        case .loaded:
            if let track = model.track {
                detail(track)
            }
        }
    }

    private func detail(_ track: Track) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                Artwork(raw: track.artworkUrl, cornerRadius: 18)
                    .frame(maxWidth: 240)
                    .aspectRatio(1, contentMode: .fit)
                    .shadow(color: .black.opacity(0.5), radius: 18, y: 8)
                    .padding(.top, 8)

                VStack(spacing: 6) {
                    Text(track.displayTitle)
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Brand.text)
                    Text(track.displayArtist)
                        .font(.title3)
                        .foregroundStyle(Brand.teal)
                        .multilineTextAlignment(.center)
                    if let album = track.displayAlbum {
                        Text(album).font(.subheadline).foregroundStyle(Brand.muted).multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal)

                HStack(spacing: 8) {
                    if track.hasDisplayOverride == true { Badge(text: "Edited", color: Brand.teal, filled: true) }
                    if track.releaseConfirmed == true { Badge(text: "Confirmed", color: Brand.gold, filled: true) }
                    MediaFormatBadge(raw: track.releaseFormat)
                }

                metadataCard(track)

                if track.hasDisplayOverride == true { providerCard(track) }

                if let plays = model.profile?.plays, !plays.isEmpty {
                    recentPlaysCard(plays)
                }

                if let fps = model.profile?.fingerprints, !fps.isEmpty {
                    InfoRow(label: "Fingerprints", value: "\(fps.count)")
                        .padding(16).grooveCard()
                }

                if let err = model.actionError {
                    Text(err).font(.caption).foregroundStyle(Brand.err).multilineTextAlignment(.center)
                }
            }
            .padding()
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .refreshable { await model.load() }
    }

    private func metadataCard(_ track: Track) -> some View {
        VStack(spacing: 0) {
            if let isrc = track.isrc?.nonEmpty { InfoRow(label: "ISRC", value: isrc, mono: true); Divider().overlay(Brand.border) }
            if let dur = track.durationMs, dur > 0 { InfoRow(label: "Duration", value: Format.duration(dur)); Divider().overlay(Brand.border) }
            if let fmt = Format.mediaFormat(track.confirmedReleaseFormat) { InfoRow(label: "Release format", value: fmt); Divider().overlay(Brand.border) }
            InfoRow(label: "Track ID", value: "\(track.id)", mono: true)
        }
        .padding(16)
        .grooveCard()
    }

    private func providerCard(_ track: Track) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Provider identified")
            VStack(spacing: 0) {
                InfoRow(label: "Title", value: track.providerTitle?.nonEmpty ?? "—")
                Divider().overlay(Brand.border)
                InfoRow(label: "Artist", value: track.providerArtist?.nonEmpty ?? "—")
                if let a = track.providerAlbum?.nonEmpty {
                    Divider().overlay(Brand.border)
                    InfoRow(label: "Album", value: a)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .grooveCard()
    }

    private func recentPlaysCard(_ plays: [Play]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Recent plays")
            ForEach(plays.prefix(6)) { play in
                Button {
                    rejectTarget = play
                } label: {
                    HStack {
                        Circle().fill(SourceStyle.color(for: play.source ?? "")).frame(width: 6, height: 6)
                        Text(Format.absolute(play.startedAt)).font(.caption).foregroundStyle(Brand.text)
                        Spacer()
                        if let source = play.source?.nonEmpty {
                            Text(SourceStyle.label(for: source)).font(.caption2).foregroundStyle(Brand.muted)
                        }
                        Image(systemName: "ellipsis.circle")
                            .font(.caption2)
                            .foregroundStyle(Brand.muted)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .grooveCard()
    }
}
