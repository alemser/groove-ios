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
            phase = .loaded
        } catch {
            phase = .error((error as? APIError)?.localizedDescription ?? error.localizedDescription)
        }
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

    @discardableResult
    func detachTracks() async -> Bool {
        guard let settings, let release else { return false }
        do {
            try await CatalogService(settings: settings).detachLibraryEditionTracks(source: release.source, releaseId: release.releaseId)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            return true
        } catch {
            actionError = (error as? APIError)?.localizedDescription ?? error.localizedDescription
            return false
        }
    }
}
