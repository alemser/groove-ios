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
        /// Scanning; `devices` lists every Oceano found so far to choose from.
        case searching
        case connecting(BLEOceanoDevice)
        case pickingNetwork
        case enteringPassword(BLEWiFiNetwork)
        case applying(ssid: String)
        case success(ssid: String, ip: String)
        case failed(String)
    }

    var phase: Phase = .searching
    var devices: [BLEOceanoDevice] = []
    var networks: [BLEWiFiNetwork] = []

    private let client = BLEProvisioningClient()
    /// The Oceano being set up; a dropped link reconnects to it, not to
    /// whichever device happens to be nearest.
    private var chosen: BLEOceanoDevice?
    private var searchTimeoutTask: Task<Void, Never>?

    /// How long a scan may find nothing before it reports so. Chosen: the
    /// bound the single-device flow used for its whole find-and-connect.
    private static let searchTimeout: Duration = .seconds(20)

    func start() {
        client.onDevicesUpdated = { [weak self] devices in
            self?.devices = devices
        }
        client.onNetworksUpdated = { [weak self] nets in
            self?.networks = nets.sorted { $0.rssi > $1.rssi }
        }
        client.onStatusUpdated = { [weak self] status in
            self?.handle(status)
        }
        search()
    }

    /// Scans for every Oceano in range. The list stays open for the user to
    /// pick from; only finding none at all within `searchTimeout` fails.
    private func search() {
        phase = .searching
        chosen = nil
        devices = []
        networks = []
        searchTimeoutTask?.cancel()
        searchTimeoutTask = Task {
            do {
                try await client.startScan()
            } catch {
                phase = .failed(error.localizedForDisplay)
                return
            }
            try? await Task.sleep(for: Self.searchTimeout)
            guard !Task.isCancelled, phase == .searching, devices.isEmpty else { return }
            client.stopScan()
            phase = .failed(BLEProvisioningError.timedOut.localizedForDisplay)
        }
    }

    func selectDevice(_ device: BLEOceanoDevice) {
        searchTimeoutTask?.cancel()
        chosen = device
        connect(to: device)
    }

    /// Runs the connect → discover-services → discover-characteristics chain
    /// to the chosen device, then requests a WiFi scan once ready. Used for
    /// the first connection *and* every reconnect — a Control write after a
    /// disconnect silently does nothing (`controlChar` is nil once torn
    /// down), which would look identical to "device not found" from the UI.
    private func connect(to device: BLEOceanoDevice) {
        phase = .connecting(device)
        networks = []
        Task {
            do {
                try await client.connect(to: device.id)
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
    /// Otherwise reconnects to the chosen device first — the link may well
    /// have dropped while the operator was reading the list.
    func rescan() {
        guard client.isReady else {
            retry()
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

    /// Retry after a failed attempt: reconnects to the device already chosen,
    /// or searches again when none was. Unlike `rescan()`, a `.failed` phase
    /// means the link is essentially guaranteed to already be down.
    func retry() {
        if let chosen {
            connect(to: chosen)
        } else {
            search()
        }
    }

    /// Back to the device list, to set up a different Oceano.
    func chooseAnotherDevice() {
        client.disconnect()
        search()
    }

    func cancel() {
        searchTimeoutTask?.cancel()
        client.disconnect()
    }
}
