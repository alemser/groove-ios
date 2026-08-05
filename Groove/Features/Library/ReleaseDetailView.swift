import SwiftUI
import Observation

@MainActor
@Observable
final class ReleaseDetailModel {
    var edition: PendingRelease?
    /// The actual catalog tracks pinned to this release (real IDs, so rows can
    /// navigate into `TrackDetailView`) — separate from `edition.tracklist`,
    /// which is provider reference data (position/title/isrc) with no track ID
    /// of its own. Matched to tracklist entries by ISRC/title in `trackId(for:)`.
    var catalogTracks: [Track] = []
    var phase: Phase = .loading

    enum Phase: Equatable { case loading, loaded, error(String) }

    private let release: LibraryRelease
    private var settings: AppSettings?

    init(release: LibraryRelease) { self.release = release }

    func configure(_ settings: AppSettings) {
        if self.settings == nil { self.settings = settings; Task { await load() } }
    }

    func load() async {
        guard let settings else { return }
        phase = .loading
        do {
            let service = CatalogService(settings: settings)
            async let editionResult = service.confirmedEdition(source: release.source, releaseId: release.releaseId)
            async let tracksResult = service.releaseTracks(source: release.source, releaseId: release.releaseId)
            edition = try await editionResult
            catalogTracks = (try? await tracksResult) ?? []
            phase = .loaded
        } catch {
            phase = .error((error as? APIError)?.localizedDescription ?? error.localizedDescription)
        }
    }

    /// Best-effort match from a provider tracklist entry to a real catalog
    /// track: ISRC is unambiguous when both sides have one, otherwise fall
    /// back to a case/whitespace-insensitive title match. Returns nil (row
    /// stays non-navigable) when no catalog track corresponds to this entry —
    /// e.g. a track listed by the provider that was never actually recognized.
    func trackId(for entry: TracklistEntry) -> Int64? {
        if let isrc = entry.isrc?.nonEmpty {
            if let match = catalogTracks.first(where: { $0.isrc?.nonEmpty == isrc }) {
                return match.id
            }
        }
        guard let title = entry.title?.nonEmpty?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
            return nil
        }
        return catalogTracks.first { ($0.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == title }?.id
    }
}

struct ReleaseDetailView: View {
    let release: LibraryRelease

    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @Environment(NowPlayingModel.self) private var nowPlaying
    @State private var model: ReleaseDetailModel
    @State private var showDeleteConfirm = false
    @State private var deleting = false
    @State private var errorMessage: String?
    @State private var showEditSheet = false

    init(release: LibraryRelease) {
        self.release = release
        _model = State(initialValue: ReleaseDetailModel(release: release))
    }

    /// The library listing only carries a summary; the confirmed edition
    /// (fetched for the tracklist anyway) often has richer metadata, so fall
    /// back to it for anything the summary left blank.
    private var year: String? {
        if let y = release.year?.nonEmpty { return y }
        guard let date = model.edition?.releaseDate?.nonEmpty, date.count >= 4 else { return nil }
        return String(date.prefix(4))
    }
    private var label: String? { release.label?.nonEmpty ?? model.edition?.label?.nonEmpty }
    private var country: String? { release.country?.nonEmpty ?? model.edition?.country?.nonEmpty }
    private var releaseType: String? { model.edition?.releaseType?.nonEmpty?.capitalized }
    private var isVinyl: Bool { (release.releaseFormat ?? "").lowercased() == "vinyl" }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Artwork(raw: release.artworkUrl, cornerRadius: 18)
                    .frame(maxWidth: 260)
                    .aspectRatio(1, contentMode: .fit)
                    .shadow(color: .black.opacity(0.5), radius: 18, y: 8)
                    .padding(.top, 8)

                VStack(spacing: 6) {
                    Text(release.album)
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Brand.text)
                    Text(release.artist)
                        .font(.title3)
                        .foregroundStyle(Brand.teal)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal)

                HStack(spacing: 8) {
                    MediaFormatBadge(raw: release.releaseFormat)
                }

                if year != nil || label != nil || country != nil || releaseType != nil {
                    VStack(spacing: 0) {
                        if let year { InfoRow(label: "Year", value: year); Divider().overlay(Brand.border) }
                        if let releaseType { InfoRow(label: "Type", value: releaseType); Divider().overlay(Brand.border) }
                        if let label { InfoRow(label: "Label", value: label); Divider().overlay(Brand.border) }
                        if let country { InfoRow(label: "Country", value: country) }
                    }
                    .padding(16)
                    .grooveCard()
                }

                tracklistSection

                if release.deletable {
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label(deleting ? "Removing…" : "Remove from Library", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(Brand.err)
                    .disabled(deleting)
                }

                if let errorMessage {
                    Text(errorMessage).font(.caption).foregroundStyle(Brand.err).multilineTextAlignment(.center)
                }
            }
            .padding()
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .grooveScreenBackground()
        .navigationTitle(release.album)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { showEditSheet = true }
            }
        }
        .confirmationDialog("Remove this edition from your library?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Remove", role: .destructive) { Task { await delete() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Catalog metadata is preserved; only this library edition is removed.")
        }
        .sheet(isPresented: $showEditSheet) {
            EditReleaseView(release: release) {
                Task { await model.load() }
            }
        }
        .task { model.configure(settings) }
    }

    @ViewBuilder
    private var tracklistSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Tracklist")
            switch model.phase {
            case .loading:
                ProgressView().tint(Brand.muted).frame(maxWidth: .infinity).padding(.vertical, 8)
            case let .error(message):
                Text(message).font(.caption).foregroundStyle(Brand.err)
            case .loaded:
                let tracklist = model.edition?.tracklist?.sorted { $0.ordinal < $1.ordinal } ?? []
                if tracklist.isEmpty {
                    Text("No tracklist available for this edition.")
                        .font(.caption)
                        .foregroundStyle(Brand.muted)
                } else if isVinyl, let sides = vinylSides(tracklist) {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(sides, id: \.side) { group in
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Side \(group.side)")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Brand.muted)
                                    .textCase(.uppercase)
                                    .tracking(0.6)
                                trackRows(group.entries)
                            }
                        }
                    }
                } else {
                    trackRows(tracklist)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .grooveCard()
    }

    /// Whether `entry` is the track currently playing on the rig. Prefers an
    /// exact catalog track-ID match, but that depends on this specific track
    /// being tagged to *this* release edition's external ID — a play can be
    /// correctly recognized (right title/artist in the mini-bar) while still
    /// living under a different release_id in the catalog, e.g. matched via
    /// a different provider/edition. Falls back to a title(+artist) compare
    /// against the live playback so the highlight doesn't depend on that link.
    private func isPlaying(_ entry: TracklistEntry, resolvedTrackId: Int64?) -> Bool {
        guard let pb = nowPlaying.status?.playback, pb.active else { return false }
        if let resolvedTrackId, let pbId = pb.trackId, pbId > 0 {
            return resolvedTrackId == pbId
        }
        guard let entryTitle = entry.title?.nonEmpty?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              let pbTitle = pb.title?.nonEmpty?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              entryTitle == pbTitle else { return false }
        guard let pbArtist = pb.artist?.nonEmpty?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
            return true
        }
        return pbArtist == release.artist.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func trackRows(_ entries: [TracklistEntry]) -> some View {
        VStack(spacing: 8) {
            ForEach(entries) { entry in
                let trackId = model.trackId(for: entry)
                let isPlaying = isPlaying(entry, resolvedTrackId: trackId)
                if let trackId {
                    NavigationLink(value: trackId) {
                        TracklistEntryRow(entry: entry, compact: false, isPlaying: isPlaying)
                    }
                    .buttonStyle(.plain)
                } else {
                    TracklistEntryRow(entry: entry, compact: false, isPlaying: isPlaying)
                }
                if entry.id != entries.last?.id {
                    Divider().overlay(Brand.border)
                }
            }
        }
    }

    /// Groups by the leading letter of each track's position (e.g. "A1",
    /// "B2") — only when every entry actually has one, otherwise this isn't
    /// really a multi-side vinyl tracklist (or the data's incomplete) and a
    /// flat list is more honest than a half-grouped one.
    private func vinylSides(_ tracklist: [TracklistEntry]) -> [(side: String, entries: [TracklistEntry])]? {
        var order: [String] = []
        var bySide: [String: [TracklistEntry]] = [:]
        for entry in tracklist {
            guard let first = entry.position?.first, first.isLetter else { return nil }
            let side = String(first).uppercased()
            if bySide[side] == nil { order.append(side) }
            bySide[side, default: []].append(entry)
        }
        guard order.count > 1 else { return nil }
        return order.map { (side: $0, entries: bySide[$0] ?? []) }
    }

    private func delete() async {
        deleting = true
        errorMessage = nil
        do {
            try await CatalogService(settings: settings).deleteLibraryRelease(source: release.source, releaseId: release.releaseId)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        } catch {
            errorMessage = (error as? APIError)?.localizedDescription ?? error.localizedDescription
            deleting = false
        }
    }
}
