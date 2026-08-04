import Foundation
import Network
import Observation
import dnssd

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
                guard let resolved = await Self.resolveHostPort(name: meta.name, type: meta.type, domain: meta.domain) else {
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

    nonisolated private static func extractServiceMeta(from result: NWBrowser.Result) -> (id: String, name: String, type: String, domain: String)? {
        switch result.endpoint {
        case let .service(name, type, domain, _):
            return (id: "\(name)|\(type)|\(domain)", name: name, type: type, domain: domain)
        default:
            return nil
        }
    }

    /// Resolves a Bonjour service to the hostname its SRV record advertises
    /// (e.g. `oceano.local`) rather than to an IP address. Opening a throwaway
    /// NWConnection and reading `remoteEndpoint` tended to capture an IPv6
    /// address the phone couldn't route to; handing URLSession the hostname
    /// lets it pick a reachable address family per request, and the stored
    /// setting survives DHCP lease changes.
    nonisolated private static func resolveHostPort(name: String, type: String, domain: String) async -> (host: String, port: Int)? {
        await withCheckedContinuation { continuation in
            let queue = DispatchQueue(label: "groove.discovery.resolve")
            let resolution = SRVResolution(continuation: continuation)
            let contextPtr = Unmanaged.passRetained(resolution).toOpaque()

            var ref: DNSServiceRef?
            let err = DNSServiceResolve(&ref, 0, 0, name, type, domain, { _, _, _, errorCode, _, hosttarget, port, _, _, rawContext in
                guard let rawContext else { return }
                let resolution = Unmanaged<SRVResolution>.fromOpaque(rawContext).takeUnretainedValue()
                guard errorCode == DNSServiceErrorType(kDNSServiceErr_NoError), let hosttarget else {
                    resolution.finish(nil)
                    return
                }
                var host = String(cString: hosttarget)
                if host.hasSuffix(".") { host.removeLast() }
                resolution.finish((host: host, port: Int(UInt16(bigEndian: port))))
            }, contextPtr)

            guard err == DNSServiceErrorType(kDNSServiceErr_NoError), let serviceRef = ref else {
                Unmanaged<SRVResolution>.fromOpaque(contextPtr).release()
                continuation.resume(returning: nil)
                return
            }
            resolution.serviceRef = serviceRef
            DNSServiceSetDispatchQueue(serviceRef, queue)
            // The timeout closure's strong reference also keeps `resolution`
            // alive until the once-only guard has definitely run.
            queue.asyncAfter(deadline: .now() + 5) { resolution.finish(nil) }
        }
    }
}

/// One in-flight DNSServiceResolve: the service ref, the continuation, and a
/// once-only guard. `finish` is only ever called on the resolve queue (the
/// dnssd callback and the timeout are both dispatched there), so access is
/// serialized without extra locking.
private final class SRVResolution: @unchecked Sendable {
    var serviceRef: DNSServiceRef?
    private var finished = false
    private let continuation: CheckedContinuation<(host: String, port: Int)?, Never>

    init(continuation: CheckedContinuation<(host: String, port: Int)?, Never>) {
        self.continuation = continuation
    }

    func finish(_ value: (host: String, port: Int)?) {
        guard !finished else { return }
        finished = true
        if let serviceRef {
            DNSServiceRefDeallocate(serviceRef)
            self.serviceRef = nil
        }
        continuation.resume(returning: value)
        // Balances the passRetained taken when this resolution began.
        Unmanaged.passUnretained(self).release()
    }
}
