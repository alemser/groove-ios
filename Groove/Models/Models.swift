import Foundation

// All models decode from groove-catalog JSON with `.convertFromSnakeCase`, so
// snake_case wire keys map to camelCase properties automatically.

// MARK: - Track

struct Track: Decodable, Identifiable, Hashable {
    var id: Int64
    var artist: String?
    var title: String?
    var album: String?
    var providerArtist: String?
    var providerTitle: String?
    var providerAlbum: String?
    var hasDisplayOverride: Bool?
    var isrc: String?
    var externalIds: String?
    var releaseFormat: String?
    var confirmedReleaseFormat: String?
    var userReleaseFormat: String?
    var releaseConfirmed: Bool?
    var durationMs: Int64?
    var artworkUrl: String?
    var providerName: String?
    /// Timestamp of the most recent real play, nil if this track has never
    /// actually been heard. NOT the same as `providerName == "album_programme"`:
    /// that field only records how the row was first materialized and is
    /// never overwritten by a later real recognition, so a genuinely-played
    /// track (schedule-advanced into existence, then actually heard many
    /// times since) still reads "album_programme" forever. `lastPlayAt` is
    /// the reliable signal — groove-catalog only sets it from real plays.
    var lastPlayAt: String?

    /// True only for a placeholder row groove-catalog materializes for every
    /// confirmed tracklist position (so schedule-advance has something to
    /// resolve against) that has never actually been heard.
    var isPlaceholderStub: Bool { lastPlayAt == nil }

    var displayTitle: String { title?.nonEmpty ?? "Untitled" }
    var displayArtist: String { artist?.nonEmpty ?? "Unknown artist" }
    var displayAlbum: String? { album?.nonEmpty }

    static func == (lhs: Track, rhs: Track) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct TrackDisplayPatch: Encodable {
    var displayArtist: String?
    var displayTitle: String?
    var displayAlbum: String?
    var releaseFormat: String?
    var reset: Bool?
}

struct TrackProfile: Decodable {
    var track: Track
    var fingerprints: [Fingerprint]?
    var plays: [Play]?
}

struct Fingerprint: Decodable, Identifiable, Hashable {
    var id: Int64
    var trackId: Int64
    var fingerprintVersion: String
    var fingerprintHash: String
    var offsetMs: Int64
    var createdAt: String?
}

// MARK: - Play (recognition history)

struct Play: Decodable, Identifiable, Hashable {
    var id: Int64
    var listenerEpoch: UInt64
    var trackId: Int64?
    var startedAt: String?
    var endedAt: String?
    var identifiedAt: String?
    var source: String?
    var confidence: Double?
    var reason: String?
    var artist: String?
    var title: String?
    var album: String?
    var isrc: String?
    var artworkUrl: String?
    var releaseConfirmed: Bool?
    var releaseFormat: String?
    var durationMs: Int64?

    var isIdentified: Bool { (title?.nonEmpty != nil || artist?.nonEmpty != nil) && trackId != nil }
    var displayTitle: String { title?.nonEmpty ?? reason?.humanizedReason ?? "Unidentified" }
    var displayArtist: String { artist?.nonEmpty ?? "—" }
}

// MARK: - Library release

struct LibraryRelease: Decodable, Identifiable, Hashable {
    var source: String
    var releaseId: String
    var catalogJobId: Int64?
    var artist: String
    var album: String
    var year: String?
    var releaseFormat: String?
    var label: String?
    var country: String?
    var artworkUrl: String?
    var owned: Bool
    var deletable: Bool
    var tracklistCount: Int
    var catalogTracks: Int
    var confirmedAt: String?
    /// A catalog track already confirmed to belong to this edition, if any — used as
    /// the `from_track_id` anchor when attaching another track to this release
    /// (drag-and-drop onto an album card).
    var sampleTrackId: Int64?
    /// Most recent play across this edition's tracks — the server already
    /// sorts the release list by this (falling back to `confirmedAt`), so
    /// nothing on this side needs to re-sort; kept for potential display use.
    var lastPlayedAt: String?

    var id: String { "\(source):\(releaseId)" }
}

struct LibraryReleasesResponse: Decodable {
    var releases: [LibraryRelease]
}

struct ConfirmedEditionResponse: Decodable {
    var edition: PendingRelease
    var job: EnrichJob?
}

// MARK: - Pending-release tracks (unconfirmed, awaiting review)

struct PendingReleaseTrack: Decodable, Identifiable, Hashable {
    var trackId: Int64
    var artist: String
    var album: String
    var title: String
    var lastPlayAt: String?
    var jobId: Int64?
    var jobStatus: String?
    var artworkUrl: String?

    var id: Int64 { trackId }
}

struct PendingReleaseTracksResponse: Decodable {
    var items: [PendingReleaseTrack]
}

struct TrackListResponse: Decodable {
    var items: [Track]
}

// MARK: - Enrich (metadata review)

struct EnrichJob: Decodable, Identifiable, Hashable {
    var id: Int64
    var listenerEpoch: UInt64
    var trackId: Int64?
    var isrc: String?
    var artist: String?
    var title: String?
    var album: String?
    var status: String
    var error: String?
    var createdAt: String?
    var updatedAt: String?
}

struct EnrichJobDetail: Decodable {
    var job: EnrichJob
    var releases: [PendingRelease]?
}

struct PendingRelease: Decodable, Identifiable, Hashable {
    var id: Int64
    var jobId: Int64
    var status: String
    var createdAt: String?
    // Flattened ReleaseCandidate fields
    var source: String?
    var releaseId: String?
    var releaseGroupId: String?
    var artist: String?
    var title: String?
    var album: String?
    var releaseType: String?
    var releaseFormat: String?
    var trackNumber: Int?
    var trackTotal: Int?
    var discNumber: Int?
    var durationMs: Int64?
    var releaseDate: String?
    var country: String?
    var label: String?
    var artworkUrl: String?
    var tracklist: [TracklistEntry]?

    static func == (lhs: PendingRelease, rhs: PendingRelease) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct TracklistEntry: Codable, Identifiable, Hashable {
    var position: String?
    var ordinal: Int
    var isrc: String?
    var title: String?
    var durationMs: Int64?

    var id: Int { ordinal }
}

// MARK: - User release editing (draft/confirm cycle)

/// Body for `PUT /catalog/enrich/jobs/{id}/user-release/draft`. Blank string
/// fields and a `nil` tracklist are "leave untouched" server-side — there's
/// no way to explicitly clear a field through this endpoint, so these are
/// plain (non-Optional) values that always carry the current+edited state.
struct UserReleaseDraftPatch: Encodable {
    var artist = ""
    var title = ""
    var album = ""
    var label = ""
    var releaseDate = ""
    var country = ""
    var releaseType = ""
    var releaseFormat = ""
    var notes = ""
    var artworkUrl = ""
    var tracklist: [TracklistEntry]?
}

struct UserReleaseEditionResponse: Decodable {
    var draft: PendingRelease
    var job: EnrichJob
    var persisted: Bool
    var libraryConfirmed: Bool?
}

struct UserReleaseDraftResponse: Decodable {
    var draft: PendingRelease
    var libraryConfirmed: Bool?
}

struct LibraryForkRequest: Encodable {
    var source: String
    var releaseId: String
}

struct LibraryForkResponse: Decodable {
    var draft: PendingRelease
    var job: EnrichJob
    var trackId: Int64
}

struct UserReleaseArtworkResponse: Decodable {
    var draft: PendingRelease
    var tracksUpdated: Int
}

/// Body for `POST /catalog/user-releases` — creates a scratch release from
/// nothing, the "cadastro" entry point mirroring the web studio's blank
/// "New release" form.
struct StandaloneUserReleaseRequest: Encodable {
    var artist: String
    var album: String
}

struct StandaloneUserReleaseResponse: Decodable {
    var draft: PendingRelease
    var job: EnrichJob
    var trackId: Int64
}

// MARK: - Pending associations (review queue)

struct PendingAssociation: Decodable, Identifiable, Hashable {
    var listenerEpoch: UInt64
    var startedAt: String?
    var failureReason: String?
    var playTrackId: Int64?
    var suggestedTrackId: Int64?
    var suggestedArtist: String?
    var suggestedTitle: String?
    var suggestedAlbum: String?
    var suggestion: IdentificationSuggestion?
    var fingerprintHash: String?
    var createdAt: String?
    /// Repeat plays of this same unresolved recording coalesce onto one row
    /// (groove-catalog#32b) instead of a duplicate queue entry per play.
    var playCount: Int?
    var lastSeenAt: String?

    var id: UInt64 { listenerEpoch }
}

/// Why the recognizer proposed this particular match — surfaced in the
/// association review sheet so "Accept" isn't a leap of faith.
struct IdentificationSuggestion: Decodable, Hashable {
    var source: String?
    var reason: String?
}

struct PendingAssociationsResponse: Decodable {
    var items: [PendingAssociation]
    var total: Int?
}

// MARK: - Manual identify (search + "never heard before" recovery)

struct IdentifySearchHit: Codable, Identifiable, Hashable {
    var source: String
    var artist: String?
    var title: String?
    var album: String?
    var isrc: String?
    var recordingId: String?
    var releaseId: String?
    var releaseGroupId: String?
    var releaseType: String?
    var releaseFormat: String?
    var trackNumber: Int?
    var trackTotal: Int?
    var discNumber: Int?
    var durationMs: Int64?
    var releaseDate: String?
    var country: String?
    var label: String?
    var artworkUrl: String?

    var id: String {
        "\(source):\(recordingId ?? releaseId ?? "")|\(artist ?? "")|\(title ?? "")"
    }
}

struct IdentifySearchResponse: Decodable {
    var items: [IdentifySearchHit]
}

struct ManualIdentifyResponse: Decodable {
    var listenerEpoch: UInt64
    var trackId: Int64
    var enrichJobId: Int64?
    var fingerprintLearned: Bool
}

// MARK: - Library release picker (autonomous mode / groove-identity#32)

/// A release already in the user's own library — the picker's primary search
/// surface, works fully offline (no enrichers required). Tracklist fetch and
/// its model already exist: CatalogService.confirmedEdition(source:releaseId:)
/// returns PendingRelease.tracklist ([TracklistEntry]).
struct LibraryReleaseSearchHit: Decodable, Identifiable, Hashable {
    var trackId: Int64?
    var jobId: Int64?
    var source: String?
    var releaseId: String?
    var artist: String
    var album: String
    var year: String?
    var artworkUrl: String?

    var id: String { "\(source ?? "")|\(releaseId ?? "")|\(artist)|\(album)" }
}

struct LibraryReleaseSearchResponse: Decodable {
    var items: [LibraryReleaseSearchHit]
}

/// Result of re-matching a track to a different release entirely (not the
/// same as editing fields of the currently-confirmed release).
struct ApplyReleaseResult: Decodable {
    var sourceTrackId: Int64
    var releaseSource: String?
    var releaseId: String?
    var confirmedJobIds: [Int64]?
    var applied: [Int64]
    var failed: [ApplyReleaseTrackError]?
}

struct ApplyReleaseTrackError: Decodable {
    var trackId: Int64
    var message: String
}

// MARK: - Status / health

struct CatalogStatus: Decodable {
    var playback: Playback
    var identityStatusError: String?
    var catalogSchemaVersion: Int?
    var catalogDbPath: String?
    var enricherChain: [String]?
    var identityStatusUrl: String?
}

struct Playback: Decodable {
    var active: Bool
    var epoch: UInt64?
    var trackId: Int64?
    var artist: String?
    var title: String?
    var album: String?
    var source: String?
    var positionMs: Int64?
    var durationMs: Int64?
    var remainingMs: Int64?
    var confidence: Double?
    var artworkUrl: String?
    var mediaFormat: String?
    var trackPosition: String?
    var identifiedAt: String?
    var matchOffsetMs: Int64?
    var identifyAttempt: Int?
    var captureSampleOffsetMs: Int64?
    var listenerStartedAt: String?
}

// MARK: - Enricher providers (settings)

struct EnrichersView: Decodable {
    var order: [String]?
    var chain: [EnricherSlot]
}

struct EnricherSlot: Decodable, Identifiable, Hashable {
    var id: String
    var displayName: String?
    var enabled: Bool
    var configured: Bool
    var apiKey: String?
    var params: [String: String]?
}

// MARK: - Small helpers

extension String {
    var nonEmpty: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    var humanizedReason: String? {
        switch self {
        case "no_match": return "No match"
        case "provider_error": return "Provider error"
        case "programme_end": return "Programme end"
        case "expected_next_track": return "Next track in album sequence"
        default: return nonEmpty?.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}

extension Optional where Wrapped == String {
    var nonEmpty: String? { self?.nonEmpty }
}
