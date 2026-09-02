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
    /// TEMPORARY diagnostic (2026-09-02, Phase 2 first field test) — see
    /// BLEProvisioningClient.onDebugLog. Remove once confirmed working.
    var debugLog: [String] = []

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
        client.onDebugLog = { [weak self] line in
            self?.debugLog.append(line)
        }
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

    func rescan() {
        phase = .pickingNetwork
        networks = []
        client.requestScan()
    }

    func submitPassword(_ password: String, for network: BLEWiFiNetwork) {
        phase = .applying(ssid: network.ssid)
        client.connectToNetwork(ssid: network.ssid, psk: password)
    }

    /// Back to the network list after a failed attempt — never re-derives
    /// networks locally, just asks the device to scan again.
    func retry() {
        rescan()
    }

    func cancel() {
        client.disconnect()
    }
}
