import Foundation

/// Typed facade over `APIClient` for every groove-catalog endpoint the app uses.
/// Screens depend on this, not on raw paths, so the wire contract lives in one
/// place.
struct CatalogService {
    let api: APIClient

    init(settings: AppSettings) {
        self.api = APIClient(settings: settings)
    }

    // MARK: Status

    func status() async throws -> CatalogStatus {
        try await api.get("/status")
    }

    // MARK: Tracks

    func tracks(page: Int, limit: Int = 50) async throws -> Page<Track> {
        try await api.get("/catalog/tracks", query: [
            .init(name: "page", value: String(page)),
            .init(name: "limit", value: String(limit)),
        ])
    }

    func track(id: Int64) async throws -> Track {
        try await api.get("/catalog/tracks/\(id)")
    }

    func trackProfile(id: Int64) async throws -> TrackProfile {
        try await api.get("/catalog/tracks/\(id)/profile")
    }

    @discardableResult
    func patchTrackDisplay(id: Int64, patch: TrackDisplayPatch) async throws -> Track {
        try await api.patch("/catalog/tracks/\(id)/display", body: patch)
    }

    func deleteTrack(id: Int64) async throws {
        try await api.delete("/catalog/tracks/\(id)")
    }

    func trackEnrichJob(id: Int64) async throws -> EnrichJobDetail {
        try await api.get("/catalog/tracks/\(id)/enrich-job")
    }

    // MARK: Plays

    func plays(page: Int, limit: Int = 50, includeFailed: Bool) async throws -> Page<Play> {
        try await api.get("/catalog/plays", query: [
            .init(name: "page", value: String(page)),
            .init(name: "limit", value: String(limit)),
            .init(name: "include_failed", value: includeFailed ? "true" : "false"),
        ])
    }

    func deletePlay(epoch: UInt64) async throws {
        try await api.delete("/catalog/plays/\(epoch)")
    }

    // MARK: Library releases

    func releases(query: String) async throws -> [LibraryRelease] {
        var items: [URLQueryItem] = []
        if !query.isEmpty { items.append(.init(name: "q", value: query)) }
        let resp: LibraryReleasesResponse = try await api.get("/catalog/releases", query: items)
        return resp.releases
    }

    func deleteLibraryRelease(source: String, releaseId: String) async throws {
        let s = source.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? source
        let r = releaseId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? releaseId
        try await api.delete("/catalog/library/releases/\(s)/\(r)")
    }

    // MARK: Enrich / review

    func enrichJobs(status: String?) async throws -> [EnrichJob] {
        var items: [URLQueryItem] = []
        if let status, !status.isEmpty { items.append(.init(name: "status", value: status)) }
        return try await api.get("/catalog/enrich/jobs", query: items)
    }

    func enrichJob(id: Int64) async throws -> EnrichJobDetail {
        try await api.get("/catalog/enrich/jobs/\(id)")
    }

    @discardableResult
    func confirmRelease(id: Int64) async throws -> PendingRelease {
        try await api.post("/catalog/enrich/releases/\(id)/confirm", body: Empty())
    }

    func discardRelease(id: Int64) async throws {
        try await api.postNoContent("/catalog/enrich/releases/\(id)/discard")
    }

    // MARK: Pending associations

    func pendingAssociations() async throws -> PendingAssociationsResponse {
        try await api.get("/catalog/plays/pending-association")
    }

    func associatePlay(epoch: UInt64, trackId: Int64) async throws {
        struct Body: Encodable { let trackId: Int64 }
        _ = try await api.post("/catalog/plays/\(epoch)/associate", body: Body(trackId: trackId), as: EmptyResponse.self)
    }

    func dismissPendingAssociation(epoch: UInt64) async throws {
        _ = try await api.post("/catalog/plays/\(epoch)/dismiss-pending-association", body: Empty(), as: EmptyResponse.self)
    }

    // MARK: Enricher providers (settings)

    func enrichers() async throws -> EnrichersView {
        try await api.get("/enrich/providers")
    }

    func setEnricherEnabled(id: String, enabled: Bool) async throws {
        struct Body: Encodable { let enabled: Bool }
        _ = try await api.patch("/enrich/providers/\(id)", body: Body(enabled: enabled), as: EmptyResponse.self)
    }
}
