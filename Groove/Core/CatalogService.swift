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

    // MARK: Stylus

    func stylusState() async throws -> StylusState {
        try await api.get("/catalog/stylus")
    }

    func stylusCatalog() async throws -> [StylusCatalogItem] {
        try await api.get("/catalog/stylus/catalog", as: StylusCatalogResponse.self).items
    }

    @discardableResult
    func putStylusProfile(_ req: StylusSaveRequest) async throws -> StylusState {
        try await api.put("/catalog/stylus", body: req)
    }

    @discardableResult
    func replaceStylusProfile(_ req: StylusSaveRequest) async throws -> StylusState {
        try await api.post("/catalog/stylus/replace", body: req)
    }

    // MARK: Rig (amplifier, equipment, remote — proxied to groove-rig via `/rig/*`)

    func rigStatus() async throws -> RigSnapshot {
        try await api.get("/rig/status")
    }

    /// Fires a no-body action (`power_toggle`, `volume_up/down`, `next/prev_input`, …)
    /// against a target. The server responds with the full refreshed snapshot.
    @discardableResult
    func rigAction(target: String = "amplifier", action: String) async throws -> RigSnapshot {
        try await api.post("/rig/targets/\(target)/actions/\(action)", body: Empty())
    }

    @discardableResult
    func rigSelectInput(inputId: String, currentInputId: String?) async throws -> RigSnapshot {
        try await api.post(
            "/rig/targets/amplifier/actions/select_input",
            body: RigSelectInputRequest(inputId: inputId, currentInputId: currentInputId)
        )
    }

    /// Safe, idempotent power control — waits out the amplifier's warm-up window
    /// rather than blindly toggling, unlike a raw `power_toggle` action.
    func rigEnsurePowerOn() async throws -> RigPowerStatus {
        try await api.post("/rig/observe/power/ensure_on", body: Empty())
    }

    func rigEnsurePowerOff() async throws -> RigPowerStatus {
        try await api.post("/rig/observe/power/ensure_off", body: Empty())
    }

    /// Realigns the server's notion of the active input after it was changed
    /// physically (front panel / bundled remote) rather than through this app.
    func rigResyncActiveInput(inputId: String) async throws {
        _ = try await api.post(
            "/rig/runtime/active_input",
            body: RigActiveInputRequest(inputId: inputId),
            as: EmptyResponse.self
        )
    }

    // MARK: Rig equipment

    func rigEquipment() async throws -> [RigEquipmentItem] {
        try await api.get("/rig/equipment", as: RigEquipmentListResponse.self).items
    }

    @discardableResult
    func rigCreateEquipment(_ req: RigEquipmentSaveRequest) async throws -> RigEquipmentItem {
        try await api.post("/rig/equipment", body: req)
    }

    func rigDeleteEquipment(id: String) async throws {
        try await api.delete("/rig/equipment/\(id)")
    }

    // MARK: Rig sessions (IR learn / pair)

    @discardableResult
    func rigStartLearn(targetId: String, action: String) async throws -> RigSessionSummary {
        try await api.post(
            "/rig/sessions/learn",
            body: RigLearnRequest(backendId: nil, targetId: targetId, action: action, timeoutSecs: 30)
        )
    }

    func rigSession(id: String) async throws -> RigSessionSummary {
        try await api.get("/rig/sessions/\(id)")
    }

    func rigUnlearn(target: String, action: String) async throws {
        try await api.delete("/rig/targets/\(target)/actions/\(action)")
    }

    // MARK: Recognition providers (proxied to groove-identity via `/identity/*`)

    func recognitionProviders() async throws -> RecognitionProvidersState {
        try await api.get("/identity/recognition/providers")
    }

    @discardableResult
    func setRecognitionProviderEnabled(id: String, enabled: Bool) async throws -> RecognitionProvidersState {
        try await api.patch("/identity/recognition/providers/\(id)", body: ProviderEnabledRequest(enabled: enabled))
    }

    @discardableResult
    func setRecognitionProviderCredentials(
        id: String,
        host: String?,
        apiKey: String?,
        apiSecret: String?
    ) async throws -> RecognitionProvidersState {
        try await api.put(
            "/identity/recognition/providers/\(id)/credentials",
            body: ProviderCredentialsRequest(host: host, apiKey: apiKey, apiSecret: apiSecret)
        )
    }

    @discardableResult
    func reorderRecognitionProviders(order: [String]) async throws -> RecognitionProvidersState {
        try await api.put("/identity/recognition/providers/order", body: ProviderOrderRequest(order: order))
    }
}
