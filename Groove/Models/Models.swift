import Foundation

// All models decode from groove-catalog JSON with `.convertFromSnakeCase`, so
// snake_case wire keys map to camelCase properties automatically.

// MARK: - Pagination

struct Page<Item: Decodable>: Decodable {
    var items: [Item]
    var page: Int
    var limit: Int
    var total: Int
    var totalPages: Int
}

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

    var id: String { "\(source):\(releaseId)" }
}

struct LibraryReleasesResponse: Decodable {
    var releases: [LibraryRelease]
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

struct TracklistEntry: Decodable, Identifiable, Hashable {
    var position: String?
    var ordinal: Int
    var isrc: String?
    var title: String?
    var durationMs: Int64?

    var id: Int { ordinal }
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
    var fingerprintHash: String?
    var createdAt: String?

    var id: UInt64 { listenerEpoch }
}

struct PendingAssociationsResponse: Decodable {
    var items: [PendingAssociation]
    var total: Int?
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
    var identifiedAt: String?
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
        default: return nonEmpty?.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}

extension Optional where Wrapped == String {
    var nonEmpty: String? { self?.nonEmpty }
}
