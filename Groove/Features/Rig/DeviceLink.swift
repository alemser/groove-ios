import SwiftUI
import Observation

/// DeviceLink devices (groove-rig `docs/devicelink.md`): equipment with a
/// network bridge built in, found by the rig on the LAN and added in one
/// tap, with a remote built from the device's own description — no IR
/// bridge, nothing to learn. Opt-in behind the "DeviceLink Devices" switch.
@MainActor
@Observable
final class DeviceLinkModel {
    /// The switch; nil until loaded (or on a rig without DeviceLink).
    var enabled: Bool?
    /// Every device found, added or not, while the switch is on.
    var devices: [RigDeviceLinkDevice] = []
    var isScanning = false
    var busyName: String?

    private var settings: AppSettings?
    private var messages: MessageCenter?

    /// Found and not added yet: what "Found on Your Network" offers.
    var found: [RigDeviceLinkDevice] { devices.filter { $0.added == nil } }

    func configure(_ settings: AppSettings, messages: MessageCenter) {
        self.settings = settings
        self.messages = messages
    }

    func load() async {
        guard let settings else { return }
        let service = CatalogService(settings: settings)
        do {
            enabled = try await service.rigDeviceLink().enabled
        } catch {
            // A rig without DeviceLink: no switch to show.
            enabled = nil
            return
        }
        devices = enabled == true ? ((try? await service.rigDeviceLinkDevices()) ?? devices) : []
    }

    func setEnabled(_ on: Bool) async {
        guard let settings, let messages else { return }
        let previous = enabled
        enabled = on
        let done = await messages.attempt {
            let service = CatalogService(settings: settings)
            try await service.rigSetDeviceLink(enabled: on)
            self.enabled = on
            self.devices = on ? ((try? await service.rigScanDeviceLink()) ?? []) : []
        } != nil
        if !done { enabled = previous }
    }

    func scan() async {
        guard let settings, let messages, !isScanning else { return }
        isScanning = true
        defer { isScanning = false }
        await messages.attempt { self.devices = try await CatalogService(settings: settings).rigScanDeviceLink() }
    }

    /// Adds `device` to the rig; true when it was.
    func add(_ device: RigDeviceLinkDevice) async -> Bool {
        guard let settings, let messages else { return false }
        busyName = device.name
        defer { busyName = nil }
        return await messages.attempt {
            try await CatalogService(settings: settings).rigAddDeviceLinkDevice(name: device.name)
            await self.load()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } != nil
    }
}

/// The switch, and while it's on, the devices found and not added yet.
struct DeviceLinkSections: View {
    let model: DeviceLinkModel

    var body: some View {
        if let enabled = model.enabled {
            Section {
                Toggle("DeviceLink Devices", isOn: Binding(
                    get: { enabled },
                    set: { on in Task { await model.setEnabled(on) } }
                ))
            } footer: {
                Text("For devices with a DeviceLink bridge. Leave off if you use an IR bridge only.")
                    .foregroundStyle(Brand.muted)
            }
            if enabled {
                Section {
                    ForEach(model.found) { device in
                        NavigationLink {
                            DeviceLinkDeviceView(device: device, model: model)
                        } label: {
                            DeviceLinkRow(device: device)
                        }
                    }
                    Button(model.isScanning ? "Searching…" : "Search Again") {
                        Task { await model.scan() }
                    }
                    .disabled(model.isScanning)
                } header: {
                    Text("Found on Your Network")
                } footer: {
                    if model.found.isEmpty {
                        Text("Nothing new found. Devices already added are in Amplifier › Equipment.")
                            .foregroundStyle(Brand.muted)
                    }
                }
            }
        }
    }
}

private struct DeviceLinkRow: View {
    let device: RigDeviceLinkDevice

    var body: some View {
        IconRow(
            title: device.displayName,
            subtitle: "\(device.kindLabel) · \(device.statusLabel)",
            icon: device.preview?.profileId != nil ? "hifispeaker" : "opticaldisc",
            tint: Brand.teal,
            subtitleColor: device.online ? Brand.muted : Brand.err
        )
    }
}

/// A device found on the network: what adding it would give, and Add to Rig.
struct DeviceLinkDeviceView: View {
    let device: RigDeviceLinkDevice
    let model: DeviceLinkModel

    @Environment(\.dismiss) private var dismiss
    @State private var confirmAmplifier = false

    var body: some View {
        Form {
            Section("Info") {
                InfoRow(label: "Kind", value: device.kindLabel)
                InfoRow(label: "Model", value: device.model)
                InfoRow(label: "Name", value: device.name, mono: true)
                InfoRow(label: "Address", value: device.ip, mono: true)
                InfoRow(label: "Status", value: device.statusLabel)
            }
            if let preview = device.preview {
                if preview.profileId != nil {
                    Section {
                        ForEach(preview.inputs ?? [], id: \.id) { Text($0.label) }
                    } header: {
                        Text("Inputs")
                    } footer: {
                        Text("Becomes your amplifier: its inputs and controls come from the device.")
                            .foregroundStyle(Brand.muted)
                    }
                }
                Section {
                    ForEach(preview.buttons, id: \.action) { Text($0.label) }
                } header: {
                    Text("Buttons")
                } footer: {
                    Text("Sent to the device itself, with no IR bridge and nothing to learn.")
                        .foregroundStyle(Brand.muted)
                }
                Section {
                    Button(model.busyName == device.name ? "Adding…" : "Add to Rig") {
                        if preview.profileId != nil {
                            confirmAmplifier = true
                        } else {
                            Task { if await model.add(device) { dismiss() } }
                        }
                    }
                    .disabled(model.busyName != nil)
                }
            } else {
                Section {
                    Text("Can't be added: \(device.previewError ?? "unknown reason")")
                        .foregroundStyle(Brand.err)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .grooveScreenBackground()
        .navigationTitle(device.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Add \(device.displayName) as your amplifier?", isPresented: $confirmAmplifier, titleVisibility: .visible) {
            Button("Add as Amplifier") {
                Task { if await model.add(device) { dismiss() } }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("It takes the place of your current amplifier, if you have one; that one comes back if you remove it.")
        }
    }
}

extension RigStateValue {
    /// The value as the contract says to show its type; "—" when the bridge
    /// doesn't know it (never read as off).
    var displayText: String {
        switch value {
        case .null:
            return "—"
        case .bool(let v):
            return v ? "On" : "Off"
        case .string(let v):
            return type == "enum" ? v.idWords : v
        case .array(let lines):
            return lines.map { line -> String in
                if case .string(let s) = line { return s }
                return ""
            }.joined(separator: "\n")
        case .number(let v):
            if type == "duration" {
                // Format.duration reads 0 as "no duration"; here 0 is a
                // known position (a track just started).
                return v < 0.5 ? "0:00" : Format.duration(Int64((v * 1000).rounded()))
            }
            let text = v == v.rounded() ? String(Int(v)) : String(v)
            return unit.map { "\(text) \($0)" } ?? text
        }
    }
}

/// What a DeviceLink device's bridge reports of its state, only while it
/// streams it.
struct DeviceStateSection: View {
    let state: RigDeviceState

    var body: some View {
        Section("Now") {
            ForEach(state.fields) { field in
                InfoRow(label: field.title, value: field.displayText, mono: field.isLines)
            }
        }
    }
}
