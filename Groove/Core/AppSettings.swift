import SwiftUI
import Observation

/// User-configurable connection settings, persisted in UserDefaults. The base
/// URL points at a groove-catalog server on the LAN (default port 7073).
@Observable
final class AppSettings {
    private let defaults = UserDefaults.standard
    private static let hostKey = "catalog.host"
    private static let portKey = "catalog.port"
    private static let schemeKey = "catalog.scheme"

    var host: String {
        didSet { defaults.set(host, forKey: Self.hostKey) }
    }
    var port: Int {
        didSet { defaults.set(port, forKey: Self.portKey) }
    }
    var scheme: String {
        didSet { defaults.set(scheme, forKey: Self.schemeKey) }
    }

    init() {
        host = defaults.string(forKey: Self.hostKey) ?? ""
        let storedPort = defaults.integer(forKey: Self.portKey)
        port = storedPort == 0 ? 7073 : storedPort
        scheme = defaults.string(forKey: Self.schemeKey) ?? "http"
    }

    /// True once a host has been entered — gates the app onto the setup screen.
    var isConfigured: Bool { !host.trimmingCharacters(in: .whitespaces).isEmpty }

    /// Base URL for the catalog API, or nil when unconfigured / malformed.
    var baseURL: URL? {
        let trimmed = host.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        var components = URLComponents()
        components.scheme = scheme
        components.host = trimmed
        components.port = port
        return components.url
    }

    /// Resolve an artwork reference: absolute URLs pass through, relative paths
    /// (e.g. `/catalog/artwork/tracks/12`) are joined onto the catalog base.
    func resolveArtwork(_ raw: String?) -> URL? {
        guard let raw, !raw.isEmpty else { return nil }
        if raw.hasPrefix("http://") || raw.hasPrefix("https://") {
            return URL(string: raw)
        }
        guard let baseURL else { return nil }
        return URL(string: raw, relativeTo: baseURL)?.absoluteURL
    }
}
