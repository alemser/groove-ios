import SwiftUI
import Observation

/// Drives the Wi-Fi setup (groove-provision's PROTOCOL.md). With no
/// `homeHost`, a first setup: the person joins the board's setup network in
/// Wi-Fi settings (iOS joins a network from an app only with the Hotspot
/// Configuration capability, which this app doesn't have). With one, a change
/// of network over the home network: the board opens its setup network, which
/// is what lets it take a new one.
@MainActor
@Observable
final class WifiSetupModel {
    enum Phase: Equatable {
        /// The person joins the setup network in Wi-Fi settings.
        case joinByHand
        case loading
        case pickingNetwork(note: String?)
        /// `error`: the board refused the last password, in its words.
        case enteringPassword(WifiNetwork, error: String?)
        case applying(ssid: String)
        case joined(ssid: String)
        /// A change of network after which the board stopped answering here:
        /// it's on `ssid` now.
        case moved(ssid: String)
        case failed(String)
    }

    var phase: Phase = .loading
    var networks: [WifiNetwork] = []
    var boardName = ""

    private let homeHost: String?
    private var client: WifiSetupClient?

    init(homeHost: String?) {
        self.homeHost = homeHost
    }

    var isChange: Bool { homeHost != nil }

    func start() {
        guard let homeHost else {
            phase = .joinByHand
            return
        }
        Task {
            await reach {
                let setup = try WifiSetupClient(host: homeHost)
                _ = try await setup.openSetup()
                return setup
            }
        }
    }

    /// The person says the phone is on the setup network.
    func joinedByHand() {
        Task { await reach { try WifiSetupClient(host: WifiSetup.host) } }
    }

    private func reach(_ open: () async throws -> WifiSetupClient) async {
        phase = .loading
        do {
            let setup = try await open()
            client = setup
            boardName = WifiSetup.boardName(setupSSID: try await setup.status().setup.ssid)
            await loadNetworks(note: nil)
        } catch {
            phase = .failed(error.localizedForDisplay)
        }
    }

    private func loadNetworks(note: String?) async {
        guard let client else { return }
        phase = .loading
        do {
            networks = try await client.networks()
            phase = .pickingNetwork(note: note ?? (networks.isEmpty ? "Oceano found no networks. Search again in a moment." : nil))
        } catch {
            phase = .failed(error.localizedForDisplay)
        }
    }

    func rescan() {
        Task { await loadNetworks(note: nil) }
    }

    func select(_ network: WifiNetwork) {
        if network.secure {
            phase = .enteringPassword(network, error: nil)
        } else {
            submit(network, psk: "")
        }
    }

    func submit(_ network: WifiNetwork, psk: String) {
        guard let client else { return }
        Task {
            phase = .applying(ssid: network.ssid)
            do {
                _ = try await client.join(ssid: network.ssid, psk: psk)
            } catch {
                phase = .enteringPassword(network, error: error.localizedForDisplay)
                return
            }
            let outcome = await client.awaitOutcome()
            if outcome?.state == .connected {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                phase = .joined(ssid: network.ssid)
            } else if let outcome, network.secure {
                // A refused password is fixed where it was typed, which keeps the text.
                phase = .enteringPassword(network, error: outcome.detail)
            } else if let outcome {
                await loadNetworks(note: "Didn't join \(network.ssid): \(outcome.detail)")
            } else if isChange {
                phase = .moved(ssid: network.ssid)
            } else {
                phase = .failed("Oceano didn't say whether it joined \(network.ssid). If it did, it shows up on your Wi-Fi in a minute.")
            }
        }
    }

    func retry() {
        client = nil
        start()
    }
}
