import SwiftUI
import Observation

/// Live "what's happening on the turntable right now" dashboard for autonomous
/// mode — a direct behavioral port of the web studio's Catalog session page
/// (`internal/api/static/catalog-studio-session.html`), state machine included.
@MainActor
@Observable
final class CatalogSessionModel {
    struct ConfirmedTrack: Identifiable {
        let trackId: Int64
        let artist: String
        let title: String
        let album: String
        let seenAt: Date
        var id: String { "\(trackId)-\(seenAt.timeIntervalSince1970)" }
    }

    /// Last known playback fields (artist/album/artwork/edit-link source) —
    /// persists across a silence gap once `everActive`, so the head card
    /// doesn't blank out between two sides of the same sitting.
    var lastPlayback: Playback?
    /// Non-nil only while `playback.active` — drives the progress bar.
    var livePlayback: Playback?
    var tracklist: [TracklistEntry] = []
    var currentJobId: Int64?
    var currentDraft: PendingRelease?
    var confirmedHistory: [ConfirmedTrack] = []
    var pending: [PendingAssociation] = []
    private(set) var everActive = false
    private(set) var nowOrdinal = 0
    private(set) var positionAnchoredAt = Date()

    private var lastNowOrdinal = 0
    private var tracklistForTrackId: Int64?
    private var settings: AppSettings?
    private var statusTask: Task<Void, Never>?
    private var pendingTask: Task<Void, Never>?

    /// Once a real track has played this sitting, a silence gap reads as
    /// "between tracks", never back to the empty idle state.
    var isIdle: Bool { !everActive }
    var isBetweenTracks: Bool { everActive && !(livePlayback?.active ?? false) }

    /// Tracklist highlight ordinal: the live position while playing, cleared
    /// during a gap — mirrors `renderTracklist(nowOrdinal, ...)` vs `(0, ...)`.
    var highlightOrdinal: Int { livePlayback?.active == true ? nowOrdinal : 0 }
    /// Everything through this ordinal renders "done" — survives a gap via
    /// `lastNowOrdinal` instead of resetting to "not yet".
    var doneCutoff: Int { livePlayback?.active == true ? max(0, nowOrdinal - 1) : lastNowOrdinal }

    func configure(_ settings: AppSettings) {
        guard self.settings == nil else { return }
        self.settings = settings
        start()
    }

    func start() {
        guard statusTask == nil, let settings else { return }
        let service = CatalogService(settings: settings)
        statusTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.pollStatus(service)
                try? await Task.sleep(for: .seconds(1))
            }
        }
        pendingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.loadPending(service)
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    func stop() {
        statusTask?.cancel()
        statusTask = nil
        pendingTask?.cancel()
        pendingTask = nil
    }

    /// Position in ms at `now`, interpolated between 1s polls — same pattern
    /// as `NowPlayingModel.interpolatedPositionMs`.
    func interpolatedPositionMs(at now: Date) -> Int64? {
        guard let pb = livePlayback, pb.active, let base = pb.positionMs else { return livePlayback?.positionMs }
        let elapsed = Int64(now.timeIntervalSince(positionAnchoredAt) * 1000)
        let value = base + max(0, elapsed)
        if let dur = pb.durationMs, dur > 0 { return min(value, dur) }
        return value
    }

    private func pollStatus(_ service: CatalogService) async {
        guard let status = try? await service.status() else { return }
        let pb = status.playback
        if pb.active { everActive = true }

        guard pb.active else {
            livePlayback = nil
            if !everActive {
                tracklist = []
                tracklistForTrackId = nil
            }
            return
        }

        if let trackId = pb.trackId, trackId > 0, tracklistForTrackId != trackId {
            await loadTracklist(service, trackId: trackId)
        }
        let matched = tracklist.first { $0.position != nil && $0.position == pb.trackPosition }?.ordinal ?? 0
        if matched > 0 { lastNowOrdinal = matched }
        nowOrdinal = matched
        lastPlayback = pb
        livePlayback = pb
        positionAnchoredAt = Date()
        if let trackId = pb.trackId, trackId > 0 {
            pushConfirmed(trackId: trackId, pb: pb)
        }
    }

    private func loadTracklist(_ service: CatalogService, trackId: Int64) async {
        tracklistForTrackId = trackId
        guard let resp = try? await service.confirmedEdition(trackId: trackId) else {
            tracklist = []
            currentJobId = nil
            currentDraft = nil
            return
        }
        tracklist = resp.edition.tracklist ?? []
        currentDraft = resp.edition
        currentJobId = resp.job?.id
    }

    private func pushConfirmed(trackId: Int64, pb: Playback) {
        guard confirmedHistory.first?.trackId != trackId else { return }
        confirmedHistory.insert(
            ConfirmedTrack(trackId: trackId, artist: pb.artist ?? "", title: pb.title ?? "", album: pb.album ?? "", seenAt: Date()),
            at: 0
        )
        if confirmedHistory.count > 20 {
            confirmedHistory.removeLast(confirmedHistory.count - 20)
        }
    }

    private func loadPending(_ service: CatalogService) async {
        pending = (try? await service.pendingAssociations().items) ?? pending
    }
}
