import SwiftUI
import Observation

@MainActor
@Observable
final class ReleasesModel {
    var releases: [LibraryRelease] = []
    var pending: [PendingReleaseTrack] = []
    var associationsCount = 0
    var actionError: String?
    var phase: Phase = .loading
    enum Phase: Equatable { case loading, loaded, error(String) }

    private var settings: AppSettings?
    private var searchTask: Task<Void, Never>?
    private var lastQuery = ""

    func configure(_ settings: AppSettings) {
        if self.settings == nil {
            self.settings = settings
            Task { await load(query: "") }
        }
    }

    func search(_ query: String) {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await load(query: query)
        }
    }

    func load(query: String) async {
        guard let settings else { return }
        lastQuery = query
        if releases.isEmpty && pending.isEmpty { phase = .loading }
        do {
            let service = CatalogService(settings: settings)
            async let releaseList = service.releases(query: query)
            async let pendingList = service.pendingReleaseTracks()
            async let associations = service.pendingAssociations()
            // Zero-track releases are legitimate on the web "Releases" management
            // page (where they're kept around specifically so the user can Remove
            // them), but here they're just phantom albums cluttering the library —
            // and their confirmed_at can be more recent than a real release's last
            // play, which threw off the "most recently played first" ordering too.
            releases = try await releaseList.filter { $0.catalogTracks > 0 }
            pending = try await pendingList
            associationsCount = try await associations.items.count
            phase = .loaded
        } catch {
            phase = .error((error as? APIError)?.localizedDescription ?? error.localizedDescription)
        }
    }

    /// Attaches `trackId` to `release` by copying metadata from a track it already
    /// owns — the primitive behind dragging a pending track onto an album card.
    func attach(trackId: Int64, to release: LibraryRelease) async {
        guard let settings, let fromId = release.sampleTrackId else { return }
        do {
            try await CatalogService(settings: settings).applyRelease(trackId: trackId, fromTrackId: fromId)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            await load(query: lastQuery)
        } catch {
            actionError = (error as? APIError)?.localizedDescription ?? error.localizedDescription
        }
    }

    /// Deletes several pending tracks in one go — the bulk counterpart to the
    /// one-at-a-time delete on `TrackDetailView`/`EnrichJobDetailView`, for
    /// clearing out a batch of junk recognitions at once.
    func deleteTracks(ids: Set<Int64>) async {
        guard let settings else { return }
        let service = CatalogService(settings: settings)
        await withTaskGroup(of: Void.self) { group in
            for id in ids {
                group.addTask { try? await service.deleteTrack(id: id) }
            }
        }
        await load(query: lastQuery)
    }
}

struct ReleasesView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(NowPlayingModel.self) private var nowPlaying
    @Environment(NavigationState.self) private var navigation
    @Environment(AttentionCenter.self) private var attention
    @State private var model = ReleasesModel()
    @State private var search = ""
    @State private var showAssociations = false
    @State private var showAddRelease = false
    @State private var dropTargetReleaseId: String?
    @State private var selectMode = false
    @State private var selectedTrackIds: Set<Int64> = []
    @State private var showBulkDeleteConfirm = false

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 16)]

    var body: some View {
        content
            .task { model.configure(settings) }
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Search releases")
            .onChange(of: search) { _, q in model.search(q) }
            // `AttentionCenter` polls independently of this screen, so the tab
            // badge can go from 0 to N (a new pending track/association shows
            // up server-side) while this grid keeps showing the stale,
            // already-loaded list. Reload whenever the badge count changes, or
            // whenever the user actually switches to this tab, so the badge
            // and the "Needs Review" section it describes never drift apart.
            .onChange(of: attention.count) { _, _ in Task { await model.load(query: search) } }
            .onChange(of: navigation.selectedTab) { _, tab in
                if tab == .library { Task { await model.load(query: search) } }
            }
            .sheet(isPresented: $showAssociations, onDismiss: { Task { await model.load(query: search) } }) {
                AssociationReviewSheet()
            }
            .sheet(isPresented: $showAddRelease, onDismiss: { Task { await model.load(query: search) } }) {
                AddReleaseView {}
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAddRelease = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add Release")
                }
                if !filteredPending.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(selectMode ? "Cancel" : "Select") {
                            selectMode.toggle()
                            if !selectMode { selectedTrackIds.removeAll() }
                        }
                    }
                }
            }
            .confirmationDialog(
                "Delete \(selectedTrackIds.count) track\(selectedTrackIds.count == 1 ? "" : "s")?",
                isPresented: $showBulkDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    let ids = selectedTrackIds
                    Task {
                        await model.deleteTracks(ids: ids)
                        selectedTrackIds.removeAll()
                        selectMode = false
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Plays are detached and enrich jobs cleaned up. This can't be undone.")
            }
    }

    private var filteredPending: [PendingReleaseTrack] {
        guard !search.isEmpty else { return model.pending }
        let q = search.lowercased()
        return model.pending.filter {
            $0.title.lowercased().contains(q) || $0.artist.lowercased().contains(q) || $0.album.lowercased().contains(q)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loading:
            LoadingView()
        case let .error(message):
            ErrorStateView(message: message) { Task { await model.load(query: search) } }
        case .loaded:
            if model.releases.isEmpty && filteredPending.isEmpty {
                EmptyStateView(icon: "square.stack", title: search.isEmpty ? "No releases" : "No matches",
                               message: search.isEmpty ? "Recognized tracks land here once their release is confirmed." : nil)
            } else {
                grid
            }
        }
    }

    private var grid: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let pb = nowPlaying.status?.playback, pb.active {
                    nowPlayingBanner(pb)
                }

                if model.associationsCount > 0 {
                    associationsBanner
                }

                if !filteredPending.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            SectionLabel(text: "Needs Review (\(filteredPending.count))")
                            Spacer()
                            if selectMode {
                                Button(selectedTrackIds.count == filteredPending.count ? "Deselect All" : "Select All") {
                                    if selectedTrackIds.count == filteredPending.count {
                                        selectedTrackIds.removeAll()
                                    } else {
                                        selectedTrackIds = Set(filteredPending.map(\.trackId))
                                    }
                                }
                                .font(.caption.weight(.semibold))
                            }
                        }
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(filteredPending) { track in
                                pendingCard(for: track)
                            }
                        }
                        if selectMode && !selectedTrackIds.isEmpty {
                            Button(role: .destructive) {
                                showBulkDeleteConfirm = true
                            } label: {
                                Label(
                                    "Delete \(selectedTrackIds.count) Track\(selectedTrackIds.count == 1 ? "" : "s")",
                                    systemImage: "trash"
                                )
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Brand.err)
                        }
                    }
                }

                if !model.releases.isEmpty {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(model.releases) { release in
                            NavigationLink(value: release) {
                                ReleaseCardView(release: release, isDropTarget: dropTargetReleaseId == release.id)
                            }
                            .buttonStyle(.plain)
                            .dropDestination(for: String.self) { items, _ in
                                guard let wire = items.first, let trackId = PendingTrackDropWire.decode(wire) else { return false }
                                Task { await model.attach(trackId: trackId, to: release) }
                                return true
                            } isTargeted: { targeted in
                                dropTargetReleaseId = targeted ? release.id : (dropTargetReleaseId == release.id ? nil : dropTargetReleaseId)
                            }
                        }
                    }
                }

                if let err = model.actionError {
                    Text(err).font(.caption).foregroundStyle(Brand.err)
                }
            }
            .padding()
        }
        .scrollContentBackground(.hidden)
        .refreshable { await model.load(query: search) }
    }

    @ViewBuilder
    private func pendingCard(for track: PendingReleaseTrack) -> some View {
        let isSelected = selectedTrackIds.contains(track.trackId)
        let card = PendingTrackCardView(track: track)
            .draggable(PendingTrackDropWire.encode(trackId: track.trackId)) {
                Label(track.title.nonEmpty ?? "Track", systemImage: "arrow.up.and.down.and.arrow.left.and.right")
            }
            .overlay(alignment: .topLeading) {
                if selectMode {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, isSelected ? Brand.accent : Brand.muted)
                        .padding(6)
                        .background(.ultraThinMaterial, in: Circle())
                        .padding(6)
                }
            }
            .opacity(selectMode && !isSelected ? 0.6 : 1)

        if selectMode {
            Button {
                if isSelected { selectedTrackIds.remove(track.trackId) } else { selectedTrackIds.insert(track.trackId) }
            } label: {
                card
            }
            .buttonStyle(.plain)
        } else if let jobId = track.jobId {
            NavigationLink(value: EnrichJob(
                id: jobId, listenerEpoch: 0, trackId: track.trackId, isrc: nil,
                artist: track.artist, title: track.title, album: track.album,
                status: track.jobStatus ?? "pending", error: nil, createdAt: nil, updatedAt: nil
            )) {
                card
            }
            .buttonStyle(.plain)
        } else {
            // No enrich job yet — route into the track detail screen instead,
            // whose ellipsis menu already offers Change Release (associate)
            // and Delete Track for exactly this unconfirmed state.
            NavigationLink(value: track.trackId) {
                card
            }
            .buttonStyle(.plain)
        }
    }

    /// Pinned at the top of the grid whenever something is actively playing —
    /// mirrors `oceano-player-ios`'s `NowPlayingBannerView` (artwork + title/
    /// artist + format badge + live-pulse dot, tappable into the full player)
    /// rather than relying on scroll position to surface it.
    private func nowPlayingBanner(_ pb: Playback) -> some View {
        Button {
            navigation.openNowPlaying()
        } label: {
            HStack(spacing: 12) {
                Artwork(raw: pb.artworkUrl, cornerRadius: 10)
                    .frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text(pb.title?.nonEmpty ?? "Now Playing")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Brand.text)
                        .lineLimit(1)
                    Text([pb.artist?.nonEmpty, pb.album?.nonEmpty].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(Brand.muted)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 6) {
                    MediaFormatBadge(raw: pb.mediaFormat)
                    Circle().fill(Brand.ok).frame(width: 6, height: 6)
                }
            }
            .padding(12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Brand.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Now playing: \(pb.title?.nonEmpty ?? "Unknown title"), \(pb.artist?.nonEmpty ?? "unknown artist")")
    }

    private var associationsBanner: some View {
        Button {
            showAssociations = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "waveform.badge.exclamationmark")
                    .font(.title3)
                    .foregroundStyle(Brand.warn)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(model.associationsCount) play\(model.associationsCount == 1 ? "" : "s") need\(model.associationsCount == 1 ? "s" : "") association")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Brand.text)
                    Text("The recognizer couldn't confidently match these to a track.")
                        .font(.caption)
                        .foregroundStyle(Brand.muted)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Brand.muted)
            }
            .padding(12)
            .background(Brand.warn.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Brand.warn.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Review plays needing association")
    }
}

// MARK: - Drag wire

/// String-encoded drag payload for moving a pending track onto an owned album card.
enum PendingTrackDropWire {
    private static let prefix = "groove-pending-track:"

    static func encode(trackId: Int64) -> String { "\(prefix)\(trackId)" }

    static func decode(_ value: String) -> Int64? {
        guard value.hasPrefix(prefix) else { return nil }
        return Int64(value.dropFirst(prefix.count))
    }
}

// MARK: - Cards

struct ReleaseCardView: View {
    let release: LibraryRelease
    var isDropTarget = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Artwork(raw: release.artworkUrl, cornerRadius: 12)
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    if isDropTarget {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Brand.accent, lineWidth: 2)
                    }
                }
                .animation(.easeInOut(duration: 0.15), value: isDropTarget)
            VStack(alignment: .leading, spacing: 2) {
                Text(release.album)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Brand.text)
                    .lineLimit(1)
                Text(release.artist)
                    .font(.caption)
                    .foregroundStyle(Brand.muted)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if let year = release.year?.nonEmpty {
                        Text(year).font(.caption2).foregroundStyle(Brand.muted)
                    }
                    MediaFormatBadge(raw: release.releaseFormat)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(release.album), \(release.artist)\(release.owned ? ", owned" : "")")
    }
}

struct PendingTrackCardView: View {
    let track: PendingReleaseTrack

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Artwork(raw: track.artworkUrl, cornerRadius: 12)
                .aspectRatio(1, contentMode: .fit)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Brand.border, style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                )
                .overlay(alignment: .topTrailing) {
                    statusIcon
                        .font(.caption)
                        .padding(6)
                        .background(.ultraThinMaterial, in: Circle())
                        .padding(6)
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title.nonEmpty ?? "Untitled")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Brand.text)
                    .lineLimit(1)
                Text(track.artist.nonEmpty ?? "Unknown artist")
                    .font(.caption)
                    .foregroundStyle(Brand.muted)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(track.title), \(track.artist), needs review")
    }

    private var statusIcon: some View {
        let (icon, color): (String, Color) = switch track.jobStatus {
        case "complete": ("checkmark.seal.fill", Brand.gold)
        case "enriching": ("arrow.triangle.2.circlepath", Brand.teal)
        case "failed": ("exclamationmark.triangle.fill", Brand.err)
        default: ("hourglass", Brand.warn)
        }
        return Image(systemName: icon).foregroundStyle(color)
    }
}
