import Foundation

/// The board's Wi-Fi setup, groove-provision's PROTOCOL.md. A board with no
/// working network opens a setup network named `prefix` + its name, with the
/// fixed `key`; on it the board answers at `host`. The same routes answer on
/// the home network, on port 80.
enum WifiSetup {
    static let prefix = "Oceano-"
    static let key = "oceano-setup"
    static let host = "192.168.4.1"

    /// The board's part of its setup network's name: "Oceano-A909" → "A909".
    static func boardName(setupSSID: String) -> String {
        setupSSID.hasPrefix(prefix) ? String(setupSSID.dropFirst(prefix.count)) : setupSSID
    }
}

struct WifiNetwork: Decodable, Identifiable, Equatable {
    let ssid: String
    let rssi: Int
    let secure: Bool

    var id: String { ssid }
}

struct SetupNetwork: Decodable, Equatable {
    let open: Bool
    let ssid: String
}

enum WifiState: String, Decodable {
    case idle, connecting, connected, failed
}

/// `GET /wifi`. `state` and `detail` are the last join (the SSID while
/// connecting or connected, the reason when failed); `ip` is the board's
/// home-network address now; `ssid` the saved network.
struct WifiStatus: Decodable, Equatable {
    let state: WifiState
    let detail: String
    let ip: String
    let ssid: String
    let setup: SetupNetwork

    var finished: Bool { state == .connected || state == .failed }
}

/// An error the board explained, shown as it is.
struct WifiSetupError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// The `/wifi` routes on one host.
struct WifiSetupClient {
    private let api: APIClient

    init(host: String) throws {
        guard let url = URL(string: "http://\(host)/") else { throw APIError.invalidURL }
        api = APIClient(baseURL: url)
    }

    func status() async throws -> WifiStatus {
        try await board { try await api.get("/wifi") }
    }

    /// The networks the board sees, strongest first. The board scans on the
    /// spot: a few seconds.
    func networks() async throws -> [WifiNetwork] {
        try await board { try await api.get("/wifi/networks") }
    }

    private struct JoinRequest: Encodable {
        let ssid: String
        let psk: String
    }

    /// Starts joining `ssid`; the outcome comes from `awaitOutcome`. An empty
    /// `psk` is an open network.
    func join(ssid: String, psk: String) async throws -> WifiStatus {
        try await board { try await api.put("/wifi", body: JoinRequest(ssid: ssid, psk: psk)) }
    }

    /// Opens the setup network for 10 minutes on a board that is on the home
    /// network.
    func openSetup() async throws -> WifiStatus {
        try await board { try await api.post("/wifi/setup", body: Empty()) }
    }

    /// Derived: the board gives up a join after 20 s (groove-provision's
    /// connect_timeout_secs) and may need a few more to go back to the
    /// previous network and answer again.
    static let outcomeTimeout: Duration = .seconds(40)

    /// Asks `/wifi` until the join ends, or nil when no final answer came in
    /// `timeout`. Lost answers are expected: the board's radio moves to the
    /// new network's channel while it joins, and the setup network moves with
    /// it.
    func awaitOutcome(timeout: Duration = outcomeTimeout, every: Duration = .seconds(1)) async -> WifiStatus? {
        var waited = Duration.zero
        while waited < timeout {
            try? await Task.sleep(for: every)
            waited += every
            if let status = try? await status(), status.finished { return status }
        }
        return nil
    }

    private struct BoardError: Decodable {
        let error: String
    }

    /// The board's `{"error": ...}` replaces the generic HTTP message.
    private func board<T>(_ call: () async throws -> T) async throws -> T {
        do {
            return try await call()
        } catch let error as APIError {
            if case let .http(_, body) = error,
               let said = try? JSONDecoder().decode(BoardError.self, from: Data(body.utf8)),
               !said.error.isEmpty {
                throw WifiSetupError(message: said.error)
            }
            throw error
        }
    }
}
