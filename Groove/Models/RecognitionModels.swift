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
    var chainMode: String
    var chain: [ProviderSlot]
    var builtins: [String: BuiltinProviderView]
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
