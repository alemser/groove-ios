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

    func pendingReleaseTracks(limit: Int = 200) async throws -> [PendingReleaseTrack] {
        try await api.get("/catalog/tracks/pending-release", query: [
            .init(name: "limit", value: String(limit)),
        ], as: PendingReleaseTracksResponse.self).items
    }

    /// Attaches the release that `fromTrackId`'s track already has onto `trackId` —
    /// the primitive behind dragging an unconfirmed track onto an owned album card.
    func applyRelease(trackId: Int64, fromTrackId: Int64) async throws {
        struct Body: Encodable { let fromTrackId: Int64 }
        _ = try await api.post("/catalog/tracks/\(trackId)/apply-release", body: Body(fromTrackId: fromTrackId), as: EmptyResponse.self)
    }

    /// Re-matches `trackId` to a different release candidate entirely — e.g.
    /// swapping a wrongly-picked digital match for the vinyl edition actually
    /// owned. Distinct from the draft-edit flow, which only edits fields of
    /// whichever release is already confirmed rather than picking a new one.
    @discardableResult
    func applyReleaseFromSearch(trackId: Int64, hit: IdentifySearchHit) async throws -> ApplyReleaseResult {
        try await api.post("/catalog/tracks/\(trackId)/apply-release-from-search", body: hit, as: ApplyReleaseResult.self)
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

    func confirmedEdition(source: String, releaseId: String) async throws -> PendingRelease {
        try await api.get("/catalog/releases/confirmed/edition", query: [
            .init(name: "source", value: source),
            .init(name: "release_id", value: releaseId),
        ], as: ConfirmedEditionResponse.self).edition
    }

    /// Tracklist + owning job for the release currently playing a given track —
    /// what the Catalog Session screen uses to highlight the live tracklist and
    /// build its "Edit release" deep link.
    func confirmedEdition(trackId: Int64) async throws -> ConfirmedEditionResponse {
        try await api.get("/catalog/releases/confirmed/edition", query: [
            .init(name: "track_id", value: String(trackId)),
        ])
    }

    /// Library-scoped release search for the "needs association" picker — works fully
    /// offline (no enrichers required), unlike identifySearch(). Reuses the same store
    /// this repo's own confirmed-library browsing already searches.
    func searchLibraryReleases(query: String, limit: Int = 20) async throws -> [LibraryReleaseSearchHit] {
        try await api.get("/catalog/releases/confirmed/search", query: [
            .init(name: "q", value: query),
            .init(name: "limit", value: String(limit)),
        ], as: LibraryReleaseSearchResponse.self).items
    }

    /// Resolves a pending association against a picked release + tracklist position
    /// rather than an already-known track_id — the track may never have existed
    /// before (groove-identity#32 autonomous mode's first-ever play of that position).
    @discardableResult
    func associatePlayToReleaseRow(epoch: UInt64, source: String, releaseId: String, ordinal: Int) async throws -> EmptyResponse {
        struct Body: Encodable { let source: String; let releaseId: String; let ordinal: Int }
        return try await api.post(
            "/catalog/plays/\(epoch)/associate-release",
            body: Body(source: source, releaseId: releaseId, ordinal: ordinal),
            as: EmptyResponse.self
        )
    }

    func detachLibraryEditionTracks(source: String, releaseId: String) async throws {
        let s = source.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? source
        let r = releaseId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? releaseId
        _ = try await api.post("/catalog/library/releases/\(s)/\(r)/detach-tracks", body: Empty(), as: EmptyResponse.self)
    }

    /// Unlinks ONE catalog track from an edition (fingerprints/plays/enrich
    /// jobs for just that track are dropped) while keeping its tracklist
    /// position — the release shape survives, unlike `deleteTrack`.
    func detachLibraryEditionTrack(source: String, releaseId: String, trackId: Int64) async throws {
        let s = source.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? source
        let r = releaseId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? releaseId
        _ = try await api.post("/catalog/library/releases/\(s)/\(r)/tracks/\(trackId)/detach", body: Empty(), as: EmptyResponse.self)
    }

    func releaseTracks(source: String, releaseId: String) async throws -> [Track] {
        let s = source.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? source
        let r = releaseId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? releaseId
        return try await api.get("/catalog/library/releases/\(s)/\(r)/tracks", as: TrackListResponse.self).items
    }

    // MARK: Enrich / review

    func enrichJob(id: Int64) async throws -> EnrichJobDetail {
        try await api.get("/catalog/enrich/jobs/\(id)")
    }

    @discardableResult
    func confirmRelease(id: Int64, force: Bool = false) async throws -> PendingRelease {
        var items: [URLQueryItem] = []
        if force { items.append(.init(name: "force", value: "1")) }
        return try await api.post("/catalog/enrich/releases/\(id)/confirm", query: items, body: Empty(), as: PendingRelease.self)
    }

    func discardRelease(id: Int64) async throws {
        try await api.postNoContent("/catalog/enrich/releases/\(id)/discard")
    }

    /// Turns an armed album-programme session user-confirmed so autonomous mode
    /// assigns subsequent tracks from the tracklist automatically for the rest of
    /// this sitting. Best-effort: a 409 just means no session was armed.
    func confirmAlbumProgrammeSession() async throws {
        try await api.postNoContent("/identity/album-programme/confirm-session")
    }

    // MARK: User release editing (draft/confirm cycle for an owned release)

    /// The confirmed-in-place edit path: only reachable when the release has
    /// a `catalog_job_id` (`LibraryRelease.catalogJobId`).
    func userReleaseDraft(jobId: Int64) async throws -> UserReleaseEditionResponse {
        try await api.get("/catalog/enrich/jobs/\(jobId)/user-release/draft")
    }

    /// Fallback when `userReleaseDraft` 404s (no draft persisted yet) — primes one.
    @discardableResult
    func reviseUserRelease(jobId: Int64) async throws -> UserReleaseEditionResponse {
        try await api.post("/catalog/enrich/jobs/\(jobId)/user-release/revise", body: Empty())
    }

    @discardableResult
    func saveUserReleaseDraft(jobId: Int64, _ patch: UserReleaseDraftPatch) async throws -> UserReleaseDraftResponse {
        try await api.put("/catalog/enrich/jobs/\(jobId)/user-release/draft", body: patch)
    }

    /// Always creates a *new* `user`-sourced copy — the only path available when
    /// the release has no `catalog_job_id` to edit in place through.
    @discardableResult
    func forkUserReleaseFromLibrary(source: String, releaseId: String) async throws -> LibraryForkResponse {
        try await api.post("/catalog/user-releases/fork-from-library", body: LibraryForkRequest(source: source, releaseId: releaseId))
    }

    func uploadUserReleaseArtwork(jobId: Int64, imageData: Data, filename: String, mimeType: String) async throws -> UserReleaseArtworkResponse {
        try await api.postMultipart(
            "/catalog/enrich/jobs/\(jobId)/user-release/artwork",
            fieldName: "artwork", filename: filename, mimeType: mimeType, data: imageData
        )
    }

    /// The "cadastro" entry point — creates a release from nothing but a typed
    /// artist/album, ready to be filled out through the same draft/publish cycle
    /// as any other user release.
    func createStandaloneUserRelease(artist: String, album: String) async throws -> StandaloneUserReleaseResponse {
        try await api.post("/catalog/user-releases", body: StandaloneUserReleaseRequest(artist: artist, album: album))
    }

    /// Creates a release prefilled from a picked enricher search hit — the
    /// autofilled counterpart to `createStandaloneUserRelease(artist:album:)`,
    /// mirroring the web studio's "Lookup using enrichers" pick-to-create flow.
    @discardableResult
    func createStandaloneUserRelease(from hit: IdentifySearchHit) async throws -> LibraryForkResponse {
        try await api.post("/catalog/user-releases/fork-from-search", body: hit)
    }

    // MARK: Pending associations

    func pendingAssociations() async throws -> PendingAssociationsResponse {
        try await api.get("/catalog/plays/pending-association")
    }

    func associatePlay(epoch: UInt64, trackId: Int64) async throws {
        struct Body: Encodable { let trackId: Int64 }
        _ = try await api.post("/catalog/plays/\(epoch)/associate", body: Body(trackId: trackId), as: EmptyResponse.self)
    }

    /// Accepts a server-suggested pending item, tagging the resolution `source`
    /// as `album_programme` rather than `manual` — distinct from `associatePlay`,
    /// which the identity backend always tags manual regardless of whether a
    /// suggestion existed.
    func confirmProgrammeSuggestion(epoch: UInt64) async throws {
        _ = try await api.post("/catalog/plays/\(epoch)/confirm-programme-suggestion", body: Empty(), as: EmptyResponse.self)
    }

    func dismissPendingAssociation(epoch: UInt64) async throws {
        _ = try await api.post("/catalog/plays/\(epoch)/dismiss-pending-association", body: Empty(), as: EmptyResponse.self)
    }

    /// Removes a play record outright — for rejecting an already-confirmed but
    /// wrong recognition when there's nothing worth re-identifying it as.
    func deletePlay(epoch: UInt64) async throws {
        try await api.delete("/catalog/plays/\(epoch)")
    }

    /// Free-text search across the library and enabled providers (MusicBrainz/Discogs/
    /// iTunes) for manually identifying a play — the "never heard before" recovery path.
    func identifySearch(query: String, limit: Int = 25) async throws -> [IdentifySearchHit] {
        try await api.get("/catalog/identify/search", query: [
            .init(name: "q", value: query),
            .init(name: "limit", value: String(limit)),
        ], as: IdentifySearchResponse.self).items
    }

    /// Explicit artist/album lookup — the "Add Release" screen's search, matching
    /// the web studio's "Lookup using enrichers" (separate fields, not a single
    /// free-text query, and only fired on an explicit search rather than per keystroke).
    func identifySearch(artist: String, album: String, limit: Int = 25) async throws -> [IdentifySearchHit] {
        try await api.get("/catalog/identify/search", query: [
            .init(name: "artist", value: artist),
            .init(name: "album", value: album),
            .init(name: "limit", value: String(limit)),
        ], as: IdentifySearchResponse.self).items
    }

    /// Identifies a play from scratch — creates the track, records the play, and queues
    /// enrichment — either from a picked search hit or fully typed-in metadata.
    @discardableResult
    func manualIdentify(epoch: UInt64, artist: String, title: String, album: String? = nil, hit: IdentifySearchHit? = nil) async throws -> ManualIdentifyResponse {
        struct Body: Encodable {
            let artist: String
            let title: String
            let album: String?
            let isrc: String?
            let source: String?
            let recordingId: String?
            let releaseId: String?
        }
        let body = Body(
            artist: artist, title: title, album: album?.nonEmpty ?? hit?.album,
            isrc: hit?.isrc, source: hit?.source, recordingId: hit?.recordingId, releaseId: hit?.releaseId
        )
        return try await api.post("/catalog/plays/\(epoch)/identify", body: body)
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

    @discardableResult
    func rigPatchEquipment(id: String, _ patch: RigEquipmentPatchRequest) async throws -> RigEquipmentItem {
        try await api.patch("/rig/equipment/\(id)", body: patch)
    }

    // MARK: Rig amplifier configuration & profiles

    /// Must be called fresh right before building a `rigPatchAmplifier` body —
    /// the endpoint merges by field presence, so patching from a stale/partial
    /// value silently zeroes whatever it doesn't include.
    func rigAmplifierConfig() async throws -> RigAmplifierConfig {
        try await api.get("/rig/amplifier")
    }

    @discardableResult
    func rigPatchAmplifier(_ patch: RigAmplifierConfig) async throws -> RigAmplifierConfig {
        try await api.patch("/rig/amplifier", body: patch)
    }

    func rigAmplifierProfiles() async throws -> RigAmplifierProfilesResponse {
        try await api.get("/rig/amplifier/profiles")
    }

    @discardableResult
    func rigSaveProfile(_ profile: RigStoredAmplifierProfile) async throws -> RigOkResponse {
        try await api.post("/rig/amplifier/profiles", body: profile)
    }

    func rigDeleteProfile(id: String) async throws {
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? id
        try await api.delete("/rig/amplifier/profiles?profile_id=\(encoded)")
    }

    @discardableResult
    func rigActivateProfile(id: String) async throws -> RigOkResponse {
        try await api.post("/rig/amplifier/profiles/activate", body: RigProfileActivateRequest(profileId: id))
    }

    func rigExportProfile(id: String) async throws -> RigProfileExportDoc {
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? id
        return try await api.get("/rig/amplifier/profiles/export?profile_id=\(encoded)")
    }

    @discardableResult
    func rigImportProfile(_ doc: RigProfileExportDoc) async throws -> RigOkResponse {
        try await api.post("/rig/amplifier/profiles/import", body: doc)
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

    /// Per-provider call/match/error telemetry plus local-index hit-rate KPIs —
    /// the web providers page's "Local index & warm map" usage panel.
    func recognitionObservability(days: Int = 30) async throws -> ProviderUsageRollup {
        try await api.get("/identity/observability/providers", query: [.init(name: "days", value: String(days))])
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

    @discardableResult
    func patchRecognitionSettings(chainMode: String?, minConfidence: Double?) async throws -> RecognitionProvidersState {
        struct Body: Encodable { let chainMode: String?; let minConfidence: Double? }
        return try await api.patch("/identity/recognition/settings", body: Body(chainMode: chainMode, minConfidence: minConfidence))
    }

    @discardableResult
    func setRecognitionAutonomous(_ autonomous: Bool) async throws -> RecognitionProvidersState {
        struct Body: Encodable { let autonomous: Bool }
        return try await api.patch("/identity/recognition/settings", body: Body(autonomous: autonomous))
    }

    @discardableResult
    func createCustomProvider(_ req: CustomProviderCreateRequest) async throws -> RecognitionProvidersState {
        try await api.post("/identity/recognition/custom-providers", body: req)
    }

    @discardableResult
    func updateCustomProvider(slug: String, _ cp: CustomProviderConfig) async throws -> RecognitionProvidersState {
        try await api.put("/identity/recognition/custom-providers/\(slug)", body: cp)
    }

    func deleteCustomProvider(slug: String) async throws {
        try await api.delete("/identity/recognition/custom-providers/\(slug)")
    }

    /// `sampleJSON` is the raw bytes of a JSON value pasted by the user (a sample
    /// provider response) — parsed and re-wrapped as `{"sample": <value>}` since the
    /// server expects it inline, not as a JSON-encoded string.
    func parseSample(slug: String?, sampleJSON: Data) async throws -> ParseSampleResponse {
        let parsed: Any
        do {
            parsed = try JSONSerialization.jsonObject(with: sampleJSON)
        } catch {
            throw APIError.decoding("That doesn't look like valid JSON.")
        }
        let body: Data
        do {
            body = try JSONSerialization.data(withJSONObject: ["sample": parsed])
        } catch {
            throw APIError.decoding("Couldn't re-encode the sample.")
        }
        let path = slug.map { "/identity/recognition/custom-providers/\($0)/parse-sample" } ?? "/identity/recognition/parse-sample"
        return try await api.postRawJSON(path, jsonBody: body)
    }

    // MARK: Metadata enrichers

    @discardableResult
    func reorderEnrichers(order: [String]) async throws -> EnrichersView {
        try await api.put("/enrich/providers/order", body: ProviderOrderRequest(order: order))
    }

    @discardableResult
    func setEnricherCredentials(id: String, apiKey: String?, params: [String: String]?) async throws -> EnrichersView {
        struct Body: Encodable { let name: String; let apiKey: String?; let params: [String: String]? }
        return try await api.put("/enrich/providers/\(id)/credentials", body: Body(name: id, apiKey: apiKey, params: params))
    }
}
