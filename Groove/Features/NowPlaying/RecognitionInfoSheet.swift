import SwiftUI

/// Deeper recognition detail for the currently playing track — everything the
/// compact Now Playing hero doesn't have room for (match offset, identify
/// attempt, when the listener session started), plus an on-demand ISRC
/// lookup once the play has resolved to a catalog track.
struct RecognitionInfoSheet: View {
    let playback: Playback

    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @State private var track: Track?
    @State private var loadError: String?

    var body: some View {
        NavigationStack {
            List {
                Section("Track") {
                    InfoRow(label: "Title", value: playback.title?.nonEmpty ?? "—")
                    InfoRow(label: "Artist", value: playback.artist?.nonEmpty ?? "—")
                    if let album = playback.album?.nonEmpty {
                        InfoRow(label: "Album", value: album)
                    }
                    if let fmt = Format.mediaFormat(playback.mediaFormat) {
                        InfoRow(label: "Format", value: fmt)
                    }
                    if let isrc = track?.isrc?.nonEmpty {
                        InfoRow(label: "ISRC", value: isrc, mono: true)
                    }
                    if let id = playback.trackId, id > 0 {
                        InfoRow(label: "Track ID", value: "\(id)", mono: true)
                    }
                }

                Section("Recognition") {
                    if let source = playback.source?.nonEmpty {
                        InfoRow(label: "Source", value: SourceStyle.label(for: source))
                    }
                    if let conf = Format.confidence(playback.confidence) {
                        InfoRow(label: "Confidence", value: conf)
                    }
                    if let identified = playback.identifiedAt?.nonEmpty {
                        InfoRow(label: "Identified", value: Format.absolute(identified))
                    }
                    if let started = playback.listenerStartedAt?.nonEmpty {
                        InfoRow(label: "Listening since", value: Format.absolute(started))
                    }
                    if let attempt = playback.identifyAttempt, attempt > 0 {
                        InfoRow(label: "Identify attempt", value: "#\(attempt)")
                    }
                    if let offset = playback.matchOffsetMs, offset > 0 {
                        InfoRow(label: "Match offset", value: Format.duration(offset))
                    }
                    if let offset = playback.captureSampleOffsetMs, offset > 0 {
                        InfoRow(label: "Capture sample offset", value: Format.duration(offset))
                    }
                    if let epoch = playback.epoch, epoch > 0 {
                        InfoRow(label: "Listener epoch", value: "\(epoch)", mono: true)
                    }
                }

                if let loadError {
                    Text(loadError).font(.caption).foregroundStyle(Brand.err)
                }
            }
            .scrollContentBackground(.hidden)
            .grooveScreenBackground()
            .navigationTitle("Recognition Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await loadTrack() }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func loadTrack() async {
        guard let id = playback.trackId, id > 0 else { return }
        do {
            track = try await CatalogService(settings: settings).trackProfile(id: id).track
        } catch {
            loadError = (error as? APIError)?.localizedDescription ?? error.localizedDescription
        }
    }
}
