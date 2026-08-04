import Foundation
import Network
import Observation

struct DiscoveredCatalogHost: Identifiable, Equatable {
    let id: String
    let displayName: String
    let host: String
    let port: Int
}

/// Bonjour auto-discovery for `groove-catalog` servers on the LAN — an
/// alternative to typing a host/IP by hand on first run. Browses `_http._tcp`
/// and keeps only services that actually answer `/status` with a
/// groove-catalog-shaped payload (`catalog_schema_version`), since plenty of
/// other things on a home network advertise plain HTTP.
@MainActor
@Observable
final class CatalogDiscovery {
    private(set) var hosts: [DiscoveredCatalogHost] = []
    private(set) var isBrowsing = false

    private var browser: NWBrowser?
    private var resolvedHostsByID: [String: DiscoveredCatalogHost] = [:]
    private var resolvingIDs: Set<String> = []
    private var resolvedIDs: Set<String> = []

    func startBrowsing() {
        guard !isBrowsing else { return }
        let params = NWParameters.tcp
        params.includePeerToPeer = true
        let descriptor = NWBrowser.Descriptor.bonjour(type: "_http._tcp", domain: "local.")
        let browser = NWBrowser(for: descriptor, using: params)
        self.browser = browser

        browser.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .ready: self?.isBrowsing = true
                case .failed, .cancelled: self?.isBrowsing = false
                default: break
                }
            }
        }
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor in self?.handleResults(results) }
        }
        browser.start(queue: .global(qos: .userInitiated))
    }

    func stopBrowsing() {
        browser?.cancel()
        browser = nil
        isBrowsing = false
        resolvingIDs.removeAll()
        resolvedIDs.removeAll()
        resolvedHostsByID.removeAll()
        hosts = []
    }

    private func handleResults(_ results: Set<NWBrowser.Result>) {
        let found = results.compactMap(Self.extractServiceMeta(from:))
        let seenIDs = Set(found.map(\.id))

        let stale = Set(resolvedHostsByID.keys).subtracting(seenIDs)
        for id in stale {
            resolvedHostsByID.removeValue(forKey: id)
            resolvedIDs.remove(id)
            resolvingIDs.remove(id)
        }
        hosts = Array(resolvedHostsByID.values).sorted { $0.displayName < $1.displayName }

        for meta in found {
            guard !resolvedIDs.contains(meta.id), !resolvingIDs.contains(meta.id) else { continue }
            resolvingIDs.insert(meta.id)
            Task {
                guard let resolved = await Self.resolveHostPort(for: meta.endpoint) else {
                    self.resolvingIDs.remove(meta.id)
                    return
                }
                let ok = await Self.isCatalogService(host: resolved.host, port: resolved.port)
                self.resolvingIDs.remove(meta.id)
                guard ok else { return }
                self.resolvedIDs.insert(meta.id)
                let item = DiscoveredCatalogHost(id: meta.id, displayName: meta.name, host: resolved.host, port: resolved.port)
                self.resolvedHostsByID[meta.id] = item
                self.hosts = Array(self.resolvedHostsByID.values).sorted { $0.displayName < $1.displayName }
            }
        }
    }

    private static func isCatalogService(host: String, port: Int) async -> Bool {
        guard !host.isEmpty, port > 0 else { return false }
        var components = URLComponents()
        components.scheme = "http"
        components.host = host
        components.port = port
        components.path = "/status"
        guard let url = components.url else { return false }
        var req = URLRequest(url: url)
        req.timeoutInterval = 2.5
        req.cachePolicy = .reloadIgnoringLocalCacheData
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["catalog_schema_version"] != nil else { return false }
        return true
    }

    nonisolated private static func extractServiceMeta(from result: NWBrowser.Result) -> (id: String, name: String, endpoint: NWEndpoint)? {
        switch result.endpoint {
        case let .service(name, type, domain, _):
            return (id: "\(name)|\(type)|\(domain)", name: name, endpoint: result.endpoint)
        default:
            return nil
        }
    }

    nonisolated private static func resolveHostPort(for endpoint: NWEndpoint) async -> (host: String, port: Int)? {
        await withCheckedContinuation { continuation in
            let connection = NWConnection(to: endpoint, using: .tcp)
            let queue = DispatchQueue(label: "groove.discovery.resolve")
            // Every mutation below runs on `queue` (state handler + the timeout
            // fallback are both dispatched onto it), so access is already
            // serialized — the compiler just can't see that through the closures.
            nonisolated(unsafe) var finished = false

            @Sendable func finish(_ value: (host: String, port: Int)?) {
                guard !finished else { return }
                finished = true
                connection.cancel()
                continuation.resume(returning: value)
            }

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if let path = connection.currentPath, case let .hostPort(host, port) = path.remoteEndpoint {
                        finish((host: host.debugDescription.trimmingCharacters(in: CharacterSet(charactersIn: "[]")), port: Int(port.rawValue)))
                    } else {
                        finish(nil)
                    }
                case .failed, .cancelled:
                    finish(nil)
                default:
                    break
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + 5) { finish(nil) }
        }
    }
}
