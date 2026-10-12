import SwiftUI

/// App-level settings: catalog server connection and recognition/enrichment
/// configuration. Rig stays focused on physical hardware; this is everything
/// else about how the app is wired up.
struct SettingsView: View {
    @Environment(AppSettings.self) private var settings

    @State private var showSwitchServer = false
    @State private var showBLEProvisioning = false
    @State private var pendingPower: PowerAction?
    @State private var isSendingPower = false
    @State private var powerStatus: String?
    @State private var powerError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink {
                        RecognitionProvidersScreen()
                    } label: {
                        row(
                            title: "Recognition Providers",
                            subtitle: "ACRCloud, AudD, custom providers, local fingerprints",
                            icon: "waveform.badge.magnifyingglass",
                            tint: Brand.gold
                        )
                    }
                } footer: {
                    Text("What identifies a spinning record.")
                        .foregroundStyle(Brand.muted)
                }

                Section {
                    NavigationLink {
                        EnricherSettingsView()
                    } label: {
                        row(
                            title: "Metadata Enrichers",
                            subtitle: "MusicBrainz, Discogs, iTunes",
                            icon: "text.badge.checkmark",
                            tint: Brand.teal
                        )
                    }
                } footer: {
                    Text("What fills in a confirmed track's metadata.")
                        .foregroundStyle(Brand.muted)
                }

                Section {
                    NavigationLink {
                        HealthView()
                    } label: {
                        Label("Stack Health", systemImage: "heart.text.square")
                    }
                }

                Section {
                    Button {
                        showSwitchServer = true
                    } label: {
                        deviceCard
                    }
                    .buttonStyle(.plain)
                    Button {
                        showBLEProvisioning = true
                    } label: {
                        Label("Reconfigure Wi-Fi via Bluetooth", systemImage: "wifi")
                    }
                } header: {
                    Text("Catalog Server")
                } footer: {
                    Text("Tap the device to switch to a different Oceano.")
                        .foregroundStyle(Brand.muted)
                }

                Section {
                    Button {
                        pendingPower = .restart
                    } label: {
                        Label("Restart Oceano", systemImage: "arrow.clockwise")
                    }
                    Button(role: .destructive) {
                        pendingPower = .shutDown
                    } label: {
                        Label("Shut Down Oceano", systemImage: "power")
                    }
                } header: {
                    Text("Device")
                } footer: {
                    if let powerError {
                        Text(powerError).foregroundStyle(Brand.err)
                    } else if let powerStatus {
                        Text(powerStatus).foregroundStyle(Brand.muted)
                    } else {
                        Text("After a shut down, Oceano stays off until its power is unplugged and plugged back in.")
                            .foregroundStyle(Brand.muted)
                    }
                }
                .disabled(settings.baseURL == nil || isSendingPower)

                Section {
                    Button(role: .destructive) {
                        settings.host = ""
                    } label: {
                        Label("Disconnect", systemImage: "wifi.slash")
                    }
                } footer: {
                    Text("Oceano \(appVersion)")
                }
            }
            .scrollContentBackground(.hidden)
            .grooveScreenBackground()
            .navigationTitle("Settings")
            .confirmationDialog(
                pendingPower?.title ?? "",
                isPresented: Binding(
                    get: { pendingPower != nil },
                    set: { if !$0 { pendingPower = nil } }
                ),
                titleVisibility: .visible,
                presenting: pendingPower
            ) { action in
                Button(action.verb, role: .destructive) {
                    Task { await sendPower(action) }
                }
                Button("Cancel", role: .cancel) {}
            } message: { action in
                Text(action.message)
            }
        }
        .sheet(isPresented: $showSwitchServer) {
            NavigationStack {
                ConnectView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { showSwitchServer = false }
                        }
                    }
            }
        }
        .sheet(isPresented: $showBLEProvisioning) {
            // This device is presumably already configured (you're in
            // Settings) -- always-advertise on the groove-provision side
            // means "reconfigure" is the exact same flow as first-run, just
            // reached from a different entry point.
            BLEProvisioningView()
        }
    }

    private func sendPower(_ action: PowerAction) async {
        isSendingPower = true
        defer { isSendingPower = false }
        powerError = nil
        powerStatus = nil
        let service = CatalogService(settings: settings)
        do {
            switch action {
            case .restart: try await service.rebootDevice()
            case .shutDown: try await service.powerOffDevice()
            }
            powerStatus = action.sentStatus
        } catch {
            powerError = error.localizedForDisplay
        }
    }

    private func row(title: String, subtitle: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).foregroundStyle(Brand.text)
                Text(subtitle).font(.caption).foregroundStyle(Brand.muted)
            }
        }
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        return "v\(v)"
    }

    /// The connected device, styled like ConnectView's discovered-host
    /// cards so switching between "here's what you're connected to" and
    /// "here's what else is available" reads as one consistent language.
    private var deviceCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(Brand.teal.opacity(0.15)).frame(width: 44, height: 44)
                Image(systemName: "opticaldisc.fill")
                    .foregroundStyle(Brand.teal)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(settings.deviceName.nonEmpty ?? "Oceano")
                    .font(.body.weight(.medium))
                    .foregroundStyle(Brand.text)
                if settings.baseURL != nil {
                    Text(settings.host + ":" + String(settings.port))
                        .font(.caption)
                        .foregroundStyle(Brand.muted)
                } else {
                    Text("Not connected")
                        .font(.caption)
                        .foregroundStyle(Brand.err)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Brand.muted)
        }
        .padding(.vertical, 4)
    }
}

/// The two device power actions Settings offers, with the copy each one needs.
private enum PowerAction: Identifiable {
    case restart, shutDown

    var id: Self { self }

    var title: String {
        switch self {
        case .restart: "Restart Oceano?"
        case .shutDown: "Shut down Oceano?"
        }
    }

    var verb: String {
        switch self {
        case .restart: "Restart"
        case .shutDown: "Shut Down"
        }
    }

    var message: String {
        switch self {
        case .restart: "Recognition and the display stop for about a minute while Oceano starts again."
        case .shutDown: "Oceano stays off until its power is unplugged and plugged back in."
        }
    }

    var sentStatus: String {
        switch self {
        case .restart: "Restarting. Oceano will be back in about a minute."
        case .shutDown: "Shutting down. Wait for the display to go dark before unplugging."
        }
    }
}
