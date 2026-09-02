import CoreBluetooth

/// Wire contract for groove-provision's BLE onboarding GATT service — must
/// match `internal/ble/protocol.go` in groove-provision exactly. See that
/// repo's PROTOCOL.md for the full shared spec.
enum BLEProvisioningProtocol {
    static let serviceUUID = CBUUID(string: "fc8938a5-ad31-4270-afdb-560b6a5f26b2")
    static let networksCharUUID = CBUUID(string: "1772e088-b8d2-4610-9a7e-11f488c9d33d")
    static let statusCharUUID = CBUUID(string: "ac2c16c0-c657-45fc-952e-ea790351f7aa")
    static let controlCharUUID = CBUUID(string: "c1a5841b-ddd5-442f-a180-99b09a925fbb")
}

struct BLEWiFiNetwork: Decodable, Identifiable, Hashable {
    var ssid: String
    var rssi: Int
    var secure: Bool
    var id: String { ssid }
}

struct BLEProvisioningStatus: Decodable, Equatable {
    var state: String
    var detail: String?
    var ip: String?
}

extension CBManagerState {
    /// Human-readable name for console logging (`BLEProvisioningClient.log`).
    var diagnosticName: String {
        switch self {
        case .unknown: return "unknown"
        case .resetting: return "resetting"
        case .unsupported: return "unsupported"
        case .unauthorized: return "unauthorized"
        case .poweredOff: return "poweredOff"
        case .poweredOn: return "poweredOn"
        @unknown default: return "unrecognized(\(rawValue))"
        }
    }
}

enum BLEProvisioningError: LocalizedError {
    case bluetoothUnavailable(String)
    case timedOut
    case disconnected

    var errorDescription: String? {
        switch self {
        case let .bluetoothUnavailable(msg): return msg
        case .timedOut: return "Couldn't find a nearby Oceano device in time. Make sure it's powered on and hasn't already joined a network."
        case .disconnected: return "Lost the Bluetooth connection to the Oceano device."
        }
    }
}

/// Low-level CoreBluetooth wrapper for onboarding a headless Oceano device
/// over BLE — parallel to `APIClient.swift`, `CBCentralManager`/`CBPeripheral`
/// instead of `URLSession`. Owns exactly one connection at a time.
///
/// `discoverAndConnect` bridges the whole scan→connect→discover-services→
/// discover-characteristics chain into one `async throws`, the same
/// delegate-to-continuation approach `CatalogDiscovery.swift`'s
/// `SRVResolution` uses for `DNSServiceResolve` — resumed exactly once, on
/// either full readiness or a terminal failure. Ongoing characteristic
/// updates (notify) after that use the `onNetworksUpdated`/`onStatusUpdated`
/// closures instead, since they're a stream, not a one-shot result.
@MainActor
final class BLEProvisioningClient: NSObject {
    var onNetworksUpdated: (([BLEWiFiNetwork]) -> Void)?
    var onStatusUpdated: ((BLEProvisioningStatus) -> Void)?
    var onDisconnected: (() -> Void)?

    private func log(_ message: String) {
        #if DEBUG
        print("[BLEProvisioning] \(message)")
        #endif
    }

    /// True once `discoverAndConnect` has actually succeeded and the link is
    /// still up — callers must check this before writing to Control (e.g.
    /// requesting a rescan); writing after a disconnect silently no-ops
    /// instead of failing loudly, since `controlChar` is nil.
    var isReady: Bool { peripheral != nil && controlChar != nil }

    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var networksChar: CBCharacteristic?
    private var statusChar: CBCharacteristic?
    private var controlChar: CBCharacteristic?

    private var readyContinuation: CheckedContinuation<Void, Error>?
    private var readyFinished = false
    private var timeoutTask: Task<Void, Never>?

    private static let decoder = JSONDecoder()
    private static let encoder = JSONEncoder()

    func discoverAndConnect(timeout: Duration = .seconds(20)) async throws {
        readyFinished = false
        log("Creating CBCentralManager…")
        let central = CBCentralManager(delegate: self, queue: nil)
        self.central = central

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.readyContinuation = continuation
            self.timeoutTask = Task { [weak self] in
                try? await Task.sleep(for: timeout)
                guard !Task.isCancelled else { return }
                self?.log("Timed out after \(timeout).")
                self?.finishReady(.failure(BLEProvisioningError.timedOut))
            }
        }
    }

    func disconnect() {
        if let peripheral, let central {
            central.cancelPeripheralConnection(peripheral)
        }
        teardown()
    }

    private func teardown() {
        timeoutTask?.cancel()
        timeoutTask = nil
        peripheral = nil
        networksChar = nil
        statusChar = nil
        controlChar = nil
    }

    private func finishReady(_ result: Result<Void, Error>) {
        guard !readyFinished, let continuation = readyContinuation else { return }
        readyFinished = true
        readyContinuation = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        continuation.resume(with: result)
    }

    // MARK: - Control writes

    func requestScan() { writeControl(["cmd": "scan"]) }

    func connectToNetwork(ssid: String, psk: String) {
        writeControl(psk.isEmpty ? ["cmd": "connect", "ssid": ssid] : ["cmd": "connect", "ssid": ssid, "psk": psk])
    }

    func forget() { writeControl(["cmd": "forget"]) }

    private func writeControl(_ payload: [String: String]) {
        guard let peripheral, let controlChar, let data = try? Self.encoder.encode(payload) else { return }
        peripheral.writeValue(data, for: controlChar, type: .withResponse)
    }
}

extension BLEProvisioningClient: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            log("State: \(central.state.diagnosticName) (raw \(central.state.rawValue))")
            switch central.state {
            case .poweredOn:
                // Scanning for *everything*, not filtered to our service UUID,
                // is a temporary diagnostic: it lets a mismatch (wrong UUID,
                // advertisement not actually reaching the phone, primary vs.
                // scan-response packet placement) show up as "found other
                // devices but never ours" instead of silent nothing. Narrow
                // back to `withServices: [BLEProvisioningProtocol.serviceUUID]`
                // once Phase 2 is confirmed working.
                log("Scanning (unfiltered, diagnostic mode)…")
                central.scanForPeripherals(withServices: nil, options: nil)
            case .poweredOff:
                finishReady(.failure(BLEProvisioningError.bluetoothUnavailable("Bluetooth is off. Turn it on in Settings to set up an Oceano device.")))
            case .unauthorized:
                finishReady(.failure(BLEProvisioningError.bluetoothUnavailable("Oceano needs Bluetooth access to set up a device. Enable it in Settings → Privacy → Bluetooth.")))
            case .unsupported:
                finishReady(.failure(BLEProvisioningError.bluetoothUnavailable("This device doesn't support Bluetooth Low Energy.")))
            case .resetting, .unknown:
                break
            @unknown default:
                break
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        Task { @MainActor in
            let name = peripheral.name ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? "(no name)"
            let uuids = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]) ?? []
            let uuidList = uuids.map(\.uuidString).joined(separator: ", ")
            let isTarget = uuids.contains(BLEProvisioningProtocol.serviceUUID)
            log("Found: \(name) rssi=\(RSSI) uuids=[\(uuidList)]\(isTarget ? " ← MATCH" : "")")

            guard isTarget else { return }
            central.stopScan()
            log("Connecting to \(name)…")
            self.peripheral = peripheral
            peripheral.delegate = self
            central.connect(peripheral, options: nil)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            log("Connected. Discovering services…")
            peripheral.discoverServices([BLEProvisioningProtocol.serviceUUID])
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            log("Failed to connect: \(error?.localizedDescription ?? "unknown error")")
            finishReady(.failure(error ?? BLEProvisioningError.disconnected))
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            log("Disconnected\(error.map { ": \($0.localizedDescription)" } ?? "").")
            teardown()
            onDisconnected?()
        }
    }
}

extension BLEProvisioningClient: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        Task { @MainActor in
            let found = (peripheral.services ?? []).map(\.uuid.uuidString).joined(separator: ", ")
            log("Services discovered: [\(found)]\(error.map { " error=\($0.localizedDescription)" } ?? "")")
            guard let service = peripheral.services?.first(where: { $0.uuid == BLEProvisioningProtocol.serviceUUID }) else {
                finishReady(.failure(error ?? BLEProvisioningError.disconnected))
                return
            }
            peripheral.discoverCharacteristics(
                [BLEProvisioningProtocol.networksCharUUID, BLEProvisioningProtocol.statusCharUUID, BLEProvisioningProtocol.controlCharUUID],
                for: service
            )
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        Task { @MainActor in
            let found = (service.characteristics ?? []).map(\.uuid.uuidString).joined(separator: ", ")
            log("Characteristics discovered: [\(found)]\(error.map { " error=\($0.localizedDescription)" } ?? "")")
            guard let chars = service.characteristics else {
                finishReady(.failure(error ?? BLEProvisioningError.disconnected))
                return
            }
            for c in chars {
                switch c.uuid {
                case BLEProvisioningProtocol.networksCharUUID:
                    networksChar = c
                    peripheral.setNotifyValue(true, for: c)
                case BLEProvisioningProtocol.statusCharUUID:
                    statusChar = c
                    peripheral.setNotifyValue(true, for: c)
                    peripheral.readValue(for: c)
                case BLEProvisioningProtocol.controlCharUUID:
                    controlChar = c
                default:
                    break
                }
            }
            if networksChar != nil, statusChar != nil, controlChar != nil {
                log("Ready — all 3 characteristics found.")
                finishReady(.success(()))
            } else {
                log("Missing characteristics: networks=\(networksChar != nil) status=\(statusChar != nil) control=\(controlChar != nil)")
                finishReady(.failure(BLEProvisioningError.disconnected))
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, let data = characteristic.value else { return }
        Task { @MainActor in
            switch characteristic.uuid {
            case BLEProvisioningProtocol.networksCharUUID:
                if let nets = try? Self.decoder.decode([BLEWiFiNetwork].self, from: data) {
                    onNetworksUpdated?(nets)
                }
            case BLEProvisioningProtocol.statusCharUUID:
                if let status = try? Self.decoder.decode(BLEProvisioningStatus.self, from: data) {
                    onStatusUpdated?(status)
                }
            default:
                break
            }
        }
    }
}
