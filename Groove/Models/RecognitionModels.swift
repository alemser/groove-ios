import Foundation

// MARK: - Recognition providers (wire models for the `/identity/*` proxy → groove-identity)

struct ProviderSlot: Decodable, Identifiable, Hashable {
    var id: String
    var displayName: String?
    var enabled: Bool
    var configured: Bool
}

/// Credentials form state for a built-in provider (ACRCloud/AudD); secrets
/// arrive redacted, never the real value.
struct BuiltinProviderView: Decodable {
    var name: String?
    var enabled: Bool?
    var host: String?
    var apiKey: String?
    var apiSecret: String?
    var configured: Bool
}

struct RecognitionProvidersState: Decodable {
    /// When true, groove-identity never enters this chain at all — only the
    /// local fingerprint index runs. A miss is routed to the pending-
    /// association flow ("Needs Association" in Library) instead of retrying
    /// through these providers.
    var autonomous: Bool
    var chainMode: String
    var minConfidence: Double
    var chain: [ProviderSlot]
    var builtins: [String: BuiltinProviderView]
    var customProviders: [CustomProviderConfig]
}

struct ProviderEnabledRequest: Encodable {
    var enabled: Bool
}

struct ProviderCredentialsRequest: Encodable {
    var host: String?
    var apiKey: String?
    var apiSecret: String?
}

struct ProviderOrderRequest: Encodable {
    var order: [String]
}

// MARK: - Custom recognition providers

/// Auth mode values a custom provider can use (Oceano parity).
enum CustomProviderAuthMode: String, CaseIterable, Identifiable {
    case bearerToken = "bearer_token"
    case headerToken = "header_token"
    case headerKeySecret = "header_key_secret"
    case formToken = "form_token"
    case formKeySecret = "form_key_secret"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .bearerToken: return "Bearer token"
        case .headerToken: return "Header token"
        case .headerKeySecret: return "Header key + secret"
        case .formToken: return "Form token"
        case .formKeySecret: return "Form key + secret"
        }
    }
}

struct CustomProviderAuthConfig: Codable, Hashable {
    var mode: String
    var token: String?
    var apiKey: String?
    var apiSecret: String?
    var tokenHeader: String?
    var tokenField: String?
    var keyField: String?
    var secretField: String?
    var keyHeader: String?
    var secretHeader: String?
}

struct CustomProviderRequestConfig: Codable, Hashable {
    var audioField: String?
    var timeoutSecs: Int?
}

struct CustomProviderFieldMap: Codable, Hashable {
    var title: String?
    var artist: String?
    var album: String?
    var score: String?
    var durationMs: String?
    var matchOffsetMs: String?
    var isrc: String?
}

struct CustomProviderResponseConfig: Codable, Hashable {
    var matchPath: String?
    var fields: CustomProviderFieldMap?
}

struct CustomProviderConfig: Codable, Identifiable, Hashable {
    var id: String
    var displayName: String
    var endpointUrl: String
    var auth: CustomProviderAuthConfig
    var request: CustomProviderRequestConfig?
    var response: CustomProviderResponseConfig?
}

/// Body shape for `POST /identity/recognition/custom-providers` — distinct from
/// `CustomProviderConfig` (used for reads and `PUT` updates).
struct CustomProviderCreateRequest: Encodable {
    var id: String
    var displayName: String
    var endpointUrl: String
    var auth: CustomProviderAuthConfig
    var request: CustomProviderRequestConfig
    var response: CustomProviderResponseConfig
    var enabled: Bool?
}

struct ParseSampleRecommendation: Decodable {
    var matchPath: String?
    var fields: CustomProviderFieldMap?
}

struct ParseSampleResponse: Decodable {
    var inferred: Bool
    var recommended: ParseSampleRecommendation?
    var message: String?
}

// MARK: - Recognition provider usage / observability

/// Per-provider recognition telemetry for the "Local index & providers usage"
/// panel — mirrors `internal/observability/query_providers.go`'s `ProviderUsageRow`.
struct ProviderUsageRow: Decodable, Identifiable {
    var provider: String
    var calls: Int
    var matched: Int
    var used: Int
    var noMatch: Int
    var belowConfidence: Int
    var rateLimited: Int
    var errors: Int
    var avgLatencyMs: Int
    var cloud: Bool

    var id: String { provider }
}

/// Local fingerprint-index recognition stats — mirrors `LocalIndexStats`.
struct LocalIndexStats: Decodable {
    var hits: Int
    var misses: Int
    var errors: Int
    var hitRate: Double
    var hitRateWhenFingerprint: Double
    var fingerprintedCaptures: Int
    var capturesWonByLocal: Int
}

struct LocalUsageSummary: Decodable {
    var index: LocalIndexStats
}

struct ProviderUsageRollup: Decodable {
    var periodDays: Int
    var providers: [ProviderUsageRow]
    var local: LocalUsageSummary
}
