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
    private static let deviceNameKey = "catalog.deviceName"
    private static let recognitionSetupPutOffKey = "recognitionSetupPutOff"
    private static let dismissedUpdateReleaseKey = "updates.dismissedRelease"
    private static let acknowledgedUpdateResultKey = "updates.acknowledgedResult"

    var host: String {
        didSet { defaults.set(host, forKey: Self.hostKey) }
    }
    var port: Int {
        didSet { defaults.set(port, forKey: Self.portKey) }
    }
    var scheme: String {
        didSet { defaults.set(scheme, forKey: Self.schemeKey) }
    }
    /// Friendly name from Bonjour discovery (e.g. "oceano"), shown on the
    /// Settings device card instead of a raw IP. Empty when connected via
    /// manual entry, where there's no discovered name to carry over.
    var deviceName: String {
        didSet { defaults.set(deviceName, forKey: Self.deviceNameKey) }
    }

    /// "Not Now" on Home's setup card: stop asking for a recognition provider.
    var recognitionSetupPutOff: Bool {
        didSet { defaults.set(recognitionSetupPutOff, forKey: Self.recognitionSetupPutOffKey) }
    }

    /// Per board (`updateBoardKey`): the release whose "Update available" notice was
    /// answered "Later", so it doesn't come back for that release.
    private var dismissedUpdateRelease: [String: String] {
        didSet { defaults.set(dismissedUpdateRelease, forKey: Self.dismissedUpdateReleaseKey) }
    }
    /// Per board: the last install whose outcome was shown (`UpdateResult.key`).
    private var acknowledgedUpdateResult: [String: String] {
        didSet { defaults.set(acknowledgedUpdateResult, forKey: Self.acknowledgedUpdateResultKey) }
    }

    /// The board the update memory belongs to: the stored host is its Bonjour name
    /// (or the address entered by hand), which stays the same across DHCP leases.
    private var updateBoardKey: String { host.trimmingCharacters(in: .whitespaces) }

    /// What this phone remembers about the connected board's update notices.
    var updateNoticeMemory: UpdateNoticeMemory {
        get {
            UpdateNoticeMemory(
                dismissedRelease: dismissedUpdateRelease[updateBoardKey],
                acknowledgedResult: acknowledgedUpdateResult[updateBoardKey]
            )
        }
        set {
            dismissedUpdateRelease[updateBoardKey] = newValue.dismissedRelease
            acknowledgedUpdateResult[updateBoardKey] = newValue.acknowledgedResult
        }
    }

    init() {
        host = defaults.string(forKey: Self.hostKey) ?? ""
        let storedPort = defaults.integer(forKey: Self.portKey)
        port = storedPort == 0 ? 7073 : storedPort
        scheme = defaults.string(forKey: Self.schemeKey) ?? "http"
        deviceName = defaults.string(forKey: Self.deviceNameKey) ?? ""
        recognitionSetupPutOff = defaults.bool(forKey: Self.recognitionSetupPutOffKey)
        dismissedUpdateRelease = defaults.dictionary(forKey: Self.dismissedUpdateReleaseKey) as? [String: String] ?? [:]
        acknowledgedUpdateResult = defaults.dictionary(forKey: Self.acknowledgedUpdateResultKey) as? [String: String] ?? [:]
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
