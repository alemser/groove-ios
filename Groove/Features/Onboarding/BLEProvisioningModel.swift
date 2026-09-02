import SwiftUI
import Observation

/// Drives the BLE onboarding flow (groove-provision's GATT protocol —
/// see PROTOCOL.md there) — state shaped like `LearnSessionModel`'s `State`,
/// but driven by Status characteristic notifications instead of HTTP
/// polling.
@MainActor
@Observable
final class BLEProvisioningModel {
    enum Phase: Equatable {
        case searching
        case pickingNetwork
        case enteringPassword(BLEWiFiNetwork)
        case applying(ssid: String)
        case success(ssid: String, ip: String)
        case failed(String)
    }

    var phase: Phase = .searching
    var networks: [BLEWiFiNetwork] = []

    private let client = BLEProvisioningClient()

    func start() {
        client.onNetworksUpdated = { [weak self] nets in
            self?.networks = nets.sorted { $0.rssi > $1.rssi }
        }
        client.onStatusUpdated = { [weak self] status in
            self?.handle(status)
        }
        client.onDisconnected = { [weak self] in
            // Expected once `success` is reached — the device drops its BLE
            // advertisement after joining WiFi. Anything else mid-flow is a
            // real loss of connection, not part of the happy path.
            guard let self, case .success = self.phase else { return }
        }
        connectAndScan()
    }

    /// Runs the full scan → connect → discover-services → discover-
    /// characteristics chain, then requests a WiFi scan once ready. Used for
    /// the initial connection *and* every retry — previously `retry()` only
    /// re-sent a Control write without reconnecting, which silently did
    /// nothing after any disconnect (`controlChar` is nil once torn down, so
    /// the write no-ops instead of failing loudly) and looked identical to
    /// "device not found" from the UI.
    private func connectAndScan() {
        phase = .searching
        networks = []
        Task {
            do {
                try await client.discoverAndConnect()
                phase = .pickingNetwork
                client.requestScan()
            } catch {
                phase = .failed(error.localizedForDisplay)
            }
        }
    }

    private func handle(_ status: BLEProvisioningStatus) {
        switch status.state {
        case "connecting":
            phase = .applying(ssid: status.detail ?? "")
        case "connected":
            phase = .success(ssid: status.detail ?? "", ip: status.ip ?? "")
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case "failed":
            phase = .failed(status.detail?.nonEmpty ?? "Couldn't join that network.")
        default:
            break
        }
    }

    func selectNetwork(_ network: BLEWiFiNetwork) {
        phase = .enteringPassword(network)
    }

    /// If the BLE link is still up, just asks for a fresh network list.
    /// Otherwise reconnects from scratch first — the link may well have
    /// dropped while the operator was reading the list.
    func rescan() {
        guard client.isReady else {
            connectAndScan()
            return
        }
        phase = .pickingNetwork
        networks = []
        client.requestScan()
    }

    func submitPassword(_ password: String, for network: BLEWiFiNetwork) {
        phase = .applying(ssid: network.ssid)
        client.connectToNetwork(ssid: network.ssid, psk: password)
    }

    /// Retry after a failed attempt. Always reconnects from scratch —
    /// unlike `rescan()`, a `.failed` phase means the link is essentially
    /// guaranteed to already be down.
    func retry() {
        connectAndScan()
    }

    func cancel() {
        client.disconnect()
    }
}
