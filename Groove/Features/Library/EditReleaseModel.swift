import SwiftUI
import Observation

@MainActor
@Observable
final class EditReleaseModel {
    /// The release as last loaded or saved — what the form is seeded from.
    var edition: PendingRelease?
    /// The job saves go through. `nil` for a new release until its first
    /// save creates it.
    var jobId: Int64?
    /// True when this edit landed on a *new* copy (no `catalog_job_id` to
    /// edit in place through) rather than the original release.
    var isCopy = false
    var phase: Phase = .loading
    var actionError: String?
    var isSaving = false
    var isUploadingArtwork = false
    var isDetaching = false
    var detachMessage: String?

    /// The actual catalog tracks pinned to this release (real IDs) — separate
    /// from the release's tracklist, which is provider reference data
    /// (position/title/isrc) with no track ID of its own. Matched to
    /// tracklist entries by ISRC/title in `trackId(for:)`, mirroring
    /// `ReleaseDetailModel`. Empty for a new release (no `release` to load
    /// real tracks from yet).
    var catalogTracks: [Track] = []

    enum Phase: Equatable { case loading, loaded, error(String) }

    var isNew: Bool { jobId == nil }

    private let release: LibraryRelease?
    private var settings: AppSettings?
    /// The search hit a new release was prefilled from, sent with its first
    /// save so the release keeps its origin.
    private var prefilledFrom: IdentifySearchHit?
    /// A cover picked before a new release's first save — there is nothing to
    /// attach it to until the save creates the release, so it goes up then.
    private var pendingArtwork: Data?
    /// The copy `load()` made of a reference release so there was something
    /// to edit. It is not in the library until saved; Cancel discards it.
    private var unsavedCopyId: Int64?

    init(release: LibraryRelease) { self.release = release }

    /// Editing the release behind an existing job (the catalog session's
    /// current release) — no library release to load from or detach tracks
    /// from.
    init(jobId: Int64, edition: PendingRelease) {
        self.release = nil
        self.jobId = jobId
        self.edition = edition
        self.phase = .loaded
    }

    /// A release that does not exist yet: the form starts from `prefill` and
    /// nothing is written until Save.
    init(newRelease prefill: PendingRelease, from hit: IdentifySearchHit?) {
        self.release = nil
        self.edition = prefill
        self.prefilledFrom = hit
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
            // Resolved from the durable library release, never from
            // `catalog_job_id` — that field names the job that *created* the
            // release, whose draft has long since been consumed, so opening
            // through it 404s (job gone) or races a job GC into a dangling
            // foreign key on save. `libraryReleaseEdition` is the same fix
            // the web studio already shipped for this.
            let resp = try await service.libraryReleaseEdition(source: release.source, releaseId: release.releaseId)
            if resp.job.id > 0 {
                jobId = resp.job.id
                edition = resp.draft
                isCopy = false
            } else {
                // No enrich job ever attached to this release — nothing for
                // a save to write through yet; mint one.
                let forkResp = try await service.forkUserReleaseFromLibrary(source: release.source, releaseId: release.releaseId)
                jobId = forkResp.job.id
                edition = forkResp.draft
                // The server edits an already-user-sourced release in place
                // (same release_id) when it's reopened purely by name — only
                // a genuinely foreign/reference release gets minted into a
                // new copy. Reflect whichever actually happened rather than
                // assuming every fork-from-library call produced a copy.
                isCopy = forkResp.draft.releaseId != release.releaseId
                unsavedCopyId = isCopy ? forkResp.draft.id : nil
            }
            catalogTracks = (try? await service.releaseTracks(source: release.source, releaseId: release.releaseId)) ?? []
            phase = .loaded
        } catch {
            phase = .error(error.localizedForDisplay)
        }
    }

    /// Best-effort match from a tracklist entry to a real catalog track
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

    /// Saves the form: the release is written and in the library when this
    /// returns true. A new release is created by this call, with every field.
    @discardableResult
    func save(_ fields: UserReleaseFields, force: Bool = false) async -> Bool {
        guard let settings else { return false }
        isSaving = true
        defer { isSaving = false }
        let service = CatalogService(settings: settings)
        do {
            let resp: SavedUserReleaseResponse
            if let jobId {
                resp = try await service.saveUserRelease(jobId: jobId, fields, force: force)
            } else {
                resp = try await service.saveNewUserRelease(fields, from: prefilledFrom, force: force)
            }
            jobId = resp.job.id
            edition = resp.release
            unsavedCopyId = nil
            actionError = nil
            if let data = pendingArtwork {
                pendingArtwork = nil
                if !(await uploadArtwork(data, filename: "artwork.jpg", mimeType: "image/jpeg")) {
                    actionError = "Release saved, but the cover failed: \(actionError ?? "unknown error")"
                    return false
                }
            }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            return true
        } catch {
            actionError = error.localizedForDisplay
            return false
        }
    }

    /// Leaving without saving: drops the copy `load()` made, which nobody
    /// saved. A new release needs nothing — it was never written.
    func discardUnsaved() async {
        guard let settings, let id = unsavedCopyId else { return }
        unsavedCopyId = nil
        try? await CatalogService(settings: settings).discardRelease(id: id)
    }

    @discardableResult
    func uploadArtwork(_ data: Data, filename: String, mimeType: String) async -> Bool {
        guard let settings else { return false }
        guard let jobId else {
            // Nothing to attach it to until the first save; it goes up then.
            pendingArtwork = data
            return true
        }
        isUploadingArtwork = true
        defer { isUploadingArtwork = false }
        do {
            let resp = try await CatalogService(settings: settings).uploadUserReleaseArtwork(
                jobId: jobId, imageData: data, filename: filename, mimeType: mimeType
            )
            edition = resp.draft
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            return true
        } catch {
            actionError = error.localizedForDisplay
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
            actionError = error.localizedForDisplay
            return false
        }
    }

    /// Deletes ONE catalog track outright (fingerprints, enrich jobs, play
    /// history) — destructive, and (unlike detach) also drops this track's
    /// tracklist position, so the caller must remove `entry` from the local
    /// tracklist on success.
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
            actionError = error.localizedForDisplay
            return false
        }
    }

    /// Detaches ONE catalog track from this edition — the tracklist position
    /// survives, so the caller should leave the tracklist entry alone.
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
            actionError = error.localizedForDisplay
            return false
        }
    }
}
