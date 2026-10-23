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

/// One Oceano advertising the provisioning service nearby. More than one can
/// be in range, so the user picks which to set up.
struct BLEOceanoDevice: Identifiable, Equatable {
    let id: UUID
    /// The advertised name, "Oceano-XXXX" (last 4 hex digits of the board's
    /// Bluetooth address), unique per board.
    var name: String
    /// The board's own name (its hostname, e.g. "oceano-0000") when the
    /// phone knows it and it differs from `name` — the same name the
    /// network list shows once the device is on Wi-Fi.
    var boardName: String?
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
    case connectTimedOut
    case disconnected

    var errorDescription: String? {
        switch self {
        case let .bluetoothUnavailable(msg): return msg
        case .timedOut: return "Couldn't find a nearby Oceano device in time. Make sure it's powered on and hasn't already joined a network."
        case .connectTimedOut: return "The Oceano device didn't answer over Bluetooth. Move closer to it and try again."
        case .disconnected: return "Lost the Bluetooth connection to the Oceano device."
        }
    }
}

/// Low-level CoreBluetooth wrapper for onboarding a headless Oceano device
/// over BLE — parallel to `APIClient.swift`, `CBCentralManager`/`CBPeripheral`
/// instead of `URLSession`. Scans for every Oceano in range and owns exactly
/// one connection at a time, to the one the user picked.
///
/// `startScan` and `connect(to:)` bridge their delegate chains into
/// `async throws`, the same delegate-to-continuation approach
/// `CatalogDiscovery.swift`'s `SRVResolution` uses for `DNSServiceResolve` —
/// each resumed exactly once, on success or a terminal failure. The streams
/// that follow (devices found, characteristic notifications) use the
/// `on…Updated` closures instead.
@MainActor
final class BLEProvisioningClient: NSObject {
    var onDevicesUpdated: (([BLEOceanoDevice]) -> Void)?
    var onNetworksUpdated: (([BLEWiFiNetwork]) -> Void)?
    var onStatusUpdated: ((BLEProvisioningStatus) -> Void)?

    private func log(_ message: String) {
        #if DEBUG
        print("[BLEProvisioning] \(message)")
        #endif
    }

    /// True once `connect(to:)` has actually succeeded and the link is still
    /// up — callers must check this before writing to Control (e.g.
    /// requesting a rescan); writing after a disconnect silently no-ops
    /// instead of failing loudly, since `controlChar` is nil.
    var isReady: Bool { peripheral != nil && controlChar != nil }

    private var central: CBCentralManager?
    /// Every Oceano seen since the scan started, by peripheral identifier.
    private var found: [UUID: (peripheral: CBPeripheral, device: BLEOceanoDevice)] = [:]
    private var peripheral: CBPeripheral?
    private var networksChar: CBCharacteristic?
    private var statusChar: CBCharacteristic?
    private var controlChar: CBCharacteristic?

    private var scanContinuation: CheckedContinuation<Void, Error>?
    private var readyContinuation: CheckedContinuation<Void, Error>?
    private var timeoutTask: Task<Void, Never>?

    private static let decoder = JSONDecoder()
    private static let encoder = JSONEncoder()

    /// Starts scanning and returns once the scan is running, or throws when
    /// Bluetooth is off, denied or missing. Devices then arrive on
    /// `onDevicesUpdated`.
    func startScan() async throws {
        found = [:]
        onDevicesUpdated?([])
        if let central {
            if central.state == .poweredOn {
                scan(central)
                return
            }
            // A settled state sends no further update to wait for.
            if let error = Self.unavailable(central.state) { throw error }
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.scanContinuation = continuation
            if self.central == nil {
                log("Creating CBCentralManager…")
                self.central = CBCentralManager(delegate: self, queue: nil)
            }
        }
    }

    func stopScan() {
        central?.stopScan()
    }

    /// Connects to one of the devices the scan found and runs the
    /// connect → discover-services → discover-characteristics chain.
    func connect(to id: UUID, timeout: Duration = .seconds(20)) async throws {
        guard let central, let target = found[id]?.peripheral else {
            throw BLEProvisioningError.disconnected
        }
        central.stopScan()
        log("Connecting to \(found[id]?.device.name ?? id.uuidString)…")
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.readyContinuation = continuation
            self.peripheral = target
            target.delegate = self
            central.connect(target, options: nil)
            self.timeoutTask = Task { [weak self] in
                try? await Task.sleep(for: timeout)
                guard !Task.isCancelled else { return }
                self?.log("Timed out after \(timeout).")
                self?.finishReady(.failure(BLEProvisioningError.connectTimedOut))
            }
        }
    }

    func disconnect() {
        central?.stopScan()
        if let peripheral, let central {
            central.cancelPeripheralConnection(peripheral)
        }
        teardown()
    }

    private func scan(_ central: CBCentralManager) {
        // Scanning for *everything*, not filtered to our service UUID, is a
        // temporary diagnostic: it lets a mismatch (wrong UUID, advertisement
        // not actually reaching the phone, primary vs. scan-response packet
        // placement) show up as "found other devices but never ours" instead
        // of silent nothing. Narrow back to
        // `withServices: [BLEProvisioningProtocol.serviceUUID]` once Phase 2
        // is confirmed working.
        log("Scanning (unfiltered, diagnostic mode)…")
        central.scanForPeripherals(withServices: nil, options: nil)
    }

    private func teardown() {
        timeoutTask?.cancel()
        timeoutTask = nil
        peripheral = nil
        networksChar = nil
        statusChar = nil
        controlChar = nil
    }

    private func finishScanStart(_ result: Result<Void, Error>) {
        guard let continuation = scanContinuation else { return }
        scanContinuation = nil
        continuation.resume(with: result)
    }

    private func finishReady(_ result: Result<Void, Error>) {
        guard let continuation = readyContinuation else { return }
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
            if central.state == .poweredOn {
                guard scanContinuation != nil else { return }
                scan(central)
                finishScanStart(.success(()))
            } else if let error = Self.unavailable(central.state) {
                finishScanStart(.failure(error))
            }
        }
    }

    /// Why Bluetooth can't be used in `state`, or nil while it is on or
    /// still settling (resetting, unknown).
    nonisolated private static func unavailable(_ state: CBManagerState) -> BLEProvisioningError? {
        switch state {
        case .poweredOff:
            return .bluetoothUnavailable("Bluetooth is off. Turn it on in Settings to set up an Oceano device.")
        case .unauthorized:
            return .bluetoothUnavailable("Oceano needs Bluetooth access to set up a device. Enable it in Settings → Privacy → Bluetooth.")
        case .unsupported:
            return .bluetoothUnavailable("This device doesn't support Bluetooth Low Energy.")
        case .poweredOn, .resetting, .unknown:
            return nil
        @unknown default:
            return nil
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        Task { @MainActor in
            let advertised = advertisementData[CBAdvertisementDataLocalNameKey] as? String
            let name = advertised ?? peripheral.name ?? "(no name)"
            let uuids = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]) ?? []
            let uuidList = uuids.map(\.uuidString).joined(separator: ", ")
            let isTarget = uuids.contains(BLEProvisioningProtocol.serviceUUID)
            log("Found: \(name) rssi=\(RSSI) uuids=[\(uuidList)]\(isTarget ? " ← MATCH" : "")")

            guard isTarget else { return }
            let boardName = peripheral.name.flatMap { $0 == name ? nil : $0 }
            let device = BLEOceanoDevice(id: peripheral.identifier, name: name, boardName: boardName)
            guard found[peripheral.identifier]?.device != device else { return }
            found[peripheral.identifier] = (peripheral, device)
            onDevicesUpdated?(found.values.map(\.device).sorted { $0.name < $1.name })
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
            // Expected once the device has joined Wi-Fi (it stops
            // advertising); mid-connect it fails the pending connect now
            // rather than at the timeout.
            finishReady(.failure(BLEProvisioningError.disconnected))
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
