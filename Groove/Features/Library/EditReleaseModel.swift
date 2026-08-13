import SwiftUI
import Observation

@MainActor
@Observable
final class EditReleaseModel {
    var draft: PendingRelease?
    var jobId: Int64?
    /// True when this edit landed on a *new* copy (no `catalog_job_id` to
    /// edit in place through) rather than the original release.
    var isCopy = false
    var phase: Phase = .loading
    var actionError: String?
    var isSaving = false
    var isPublishing = false
    var isUploadingArtwork = false
    var isDetaching = false
    var detachMessage: String?

    /// The actual catalog tracks pinned to this release (real IDs) — separate
    /// from the draft's tracklist, which is provider reference data
    /// (position/title/isrc) with no track ID of its own. Matched to
    /// tracklist entries by ISRC/title in `trackId(for:)`, mirroring
    /// `ReleaseDetailModel`. Empty for the from-scratch creation flow (no
    /// `release` to load real tracks from yet).
    var catalogTracks: [Track] = []

    enum Phase: Equatable { case loading, loaded, error(String) }

    private let release: LibraryRelease?
    private var settings: AppSettings?

    init(release: LibraryRelease) { self.release = release }

    /// Editing a release created moments ago via the standalone "Add Release"
    /// flow — draft + jobId already in hand from the create call, no library
    /// release to load from or detach tracks from.
    init(jobId: Int64, draft: PendingRelease) {
        self.release = nil
        self.jobId = jobId
        self.draft = draft
        self.phase = .loaded
    }

    func configure(_ settings: AppSettings) {
        guard self.settings == nil else { return }
        self.settings = settings
        if release != nil { Task { await load() } }
    }

    func load() async {
        guard let settings, let release else { return }
        phase = .loading
        let service = CatalogService(settings: settings)
        do {
            if let catalogJobId = release.catalogJobId, catalogJobId > 0 {
                do {
                    let resp = try await service.userReleaseDraft(jobId: catalogJobId)
                    jobId = catalogJobId
                    draft = resp.draft
                    isCopy = false
                } catch let error as APIError {
                    guard case let .http(status, _) = error, status == 404 else { throw error }
                    // No draft persisted yet for this job — prime one.
                    let resp = try await service.reviseUserRelease(jobId: catalogJobId)
                    jobId = catalogJobId
                    draft = resp.draft
                    isCopy = false
                }
            } else {
                let resp = try await service.forkUserReleaseFromLibrary(source: release.source, releaseId: release.releaseId)
                jobId = resp.job.id
                draft = resp.draft
                isCopy = true
            }
            catalogTracks = (try? await service.releaseTracks(source: release.source, releaseId: release.releaseId)) ?? []
            phase = .loaded
        } catch {
            phase = .error((error as? APIError)?.localizedDescription ?? error.localizedDescription)
        }
    }

    /// Best-effort match from a draft tracklist entry to a real catalog track
    /// — mirrors `ReleaseDetailModel.trackId(for:)`. Returns nil when nothing
    /// has been recognized into this position yet, or (for the from-scratch
    /// flow) there's no release to match against at all.
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

    @discardableResult
    func saveDraft(_ patch: UserReleaseDraftPatch) async -> Bool {
        guard let settings, let jobId else { return false }
        isSaving = true
        defer { isSaving = false }
        do {
            let resp = try await CatalogService(settings: settings).saveUserReleaseDraft(jobId: jobId, patch)
            draft = resp.draft
            actionError = nil
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            return true
        } catch {
            actionError = (error as? APIError)?.localizedDescription ?? error.localizedDescription
            return false
        }
    }

    @discardableResult
    func publish(force: Bool = false) async -> Bool {
        guard let settings, let draft else { return false }
        isPublishing = true
        defer { isPublishing = false }
        do {
            _ = try await CatalogService(settings: settings).confirmRelease(id: draft.id, force: force)
            actionError = nil
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            return true
        } catch {
            actionError = (error as? APIError)?.localizedDescription ?? error.localizedDescription
            return false
        }
    }

    @discardableResult
    func uploadArtwork(_ data: Data, filename: String, mimeType: String) async -> Bool {
        guard let settings, let jobId else { return false }
        isUploadingArtwork = true
        defer { isUploadingArtwork = false }
        do {
            let resp = try await CatalogService(settings: settings).uploadUserReleaseArtwork(
                jobId: jobId, imageData: data, filename: filename, mimeType: mimeType
            )
            draft = resp.draft
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            return true
        } catch {
            actionError = (error as? APIError)?.localizedDescription ?? error.localizedDescription
            return false
        }
    }

    /// Detaches every catalog track from this edition. Unlike the per-track
    /// actions below, there's no single row to update afterward — the caller
    /// needs `detachMessage` (shown inline) since a haptic alone gives no
    /// visible confirmation that ~N tracks actually disappeared.
    @discardableResult
    func detachTracks() async -> Bool {
        guard let settings, let release else { return false }
        isDetaching = true
        actionError = nil
        detachMessage = nil
        defer { isDetaching = false }
        do {
            try await CatalogService(settings: settings).detachLibraryEditionTracks(source: release.source, releaseId: release.releaseId)
            let removed = catalogTracks.count
            catalogTracks = []
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            detachMessage = removed > 0
                ? "Detached \(removed) track\(removed == 1 ? "" : "s") — the tracklist stays, ready to re-recognize."
                : "No linked tracks to detach."
            return true
        } catch {
            actionError = (error as? APIError)?.localizedDescription ?? error.localizedDescription
            return false
        }
    }

    /// Deletes ONE catalog track outright (fingerprints, enrich jobs, play
    /// history) — destructive, and (unlike detach) also drops this track's
    /// tracklist position, so the caller must remove `entry` from the local
    /// draft tracklist on success.
    @discardableResult
    func deleteTrack(_ track: Track) async -> Bool {
        guard let settings else { return false }
        actionError = nil
        do {
            try await CatalogService(settings: settings).deleteTrack(id: track.id)
            catalogTracks.removeAll { $0.id == track.id }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            return true
        } catch {
            actionError = (error as? APIError)?.localizedDescription ?? error.localizedDescription
            return false
        }
    }

    /// Detaches ONE catalog track from this edition — the tracklist position
    /// survives, so the caller should leave the draft tracklist entry alone.
    @discardableResult
    func detachTrack(_ track: Track) async -> Bool {
        guard let settings, let release else { return false }
        actionError = nil
        do {
            try await CatalogService(settings: settings).detachLibraryEditionTrack(
                source: release.source, releaseId: release.releaseId, trackId: track.id
            )
            catalogTracks.removeAll { $0.id == track.id }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            return true
        } catch {
            actionError = (error as? APIError)?.localizedDescription ?? error.localizedDescription
            return false
        }
    }
}
