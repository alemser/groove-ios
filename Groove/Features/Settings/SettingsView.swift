import SwiftUI

/// App-level settings: catalog server connection, recognition/enrichment
/// configuration and streaming, which is part of Oceano itself rather than
/// the rig around it. Rig stays focused on physical hardware; this is
/// everything else about how Oceano is wired up.
/// How a settings screen is named and drawn wherever it's offered: Settings and Home's setup card.
struct ScreenEntry {
    let title: String
    let icon: String
    let tint: Color

    static let recognitionProviders = ScreenEntry(
        title: "Recognition Providers", icon: "waveform.badge.magnifyingglass", tint: Brand.gold
    )
    static let metadataEnrichers = ScreenEntry(title: "Metadata Enrichers", icon: "text.badge.checkmark", tint: Brand.teal)
}

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(MessageCenter.self) private var messages
    @Environment(UpdateCenter.self) private var updates

    @State private var streamingStatusText: String?
    @State private var showSwitchServer = false
    @State private var showWifiSetup = false
    @State private var pendingPower: PowerAction?
    @State private var isSendingPower = false
    @State private var powerStatus: String?
    @State private var isSharingLogs = false
    @State private var sharedLog: SharedFile?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink {
                        RecognitionProvidersScreen()
                    } label: {
                        IconRow(
                            title: ScreenEntry.recognitionProviders.title,
                            subtitle: "ACRCloud, AudD, custom providers, local fingerprints",
                            icon: ScreenEntry.recognitionProviders.icon,
                            tint: ScreenEntry.recognitionProviders.tint
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
                        IconRow(
                            title: ScreenEntry.metadataEnrichers.title,
                            subtitle: "MusicBrainz, Discogs, iTunes",
                            icon: ScreenEntry.metadataEnrichers.icon,
                            tint: ScreenEntry.metadataEnrichers.tint
                        )
                    }
                } footer: {
                    Text("What fills in a confirmed track's metadata.")
                        .foregroundStyle(Brand.muted)
                }

                Section {
                    NavigationLink {
                        StreamingView()
                    } label: {
                        IconRow(
                            title: "Streaming",
                            subtitle: streamingStatusText ?? "Loading…",
                            icon: "airplayaudio",
                            tint: Brand.ok
                        )
                    }
                } footer: {
                    Text("AirPlay and Bluetooth receivers, and where they play out to the amplifier.")
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
                        // Busy from the tap, before the task runs: a second tap can't send twice.
                        isSharingLogs = true
                        Task { await shareLogs() }
                    } label: {
                        Label(isSharingLogs ? "Preparing Logs…" : "Share Logs", systemImage: "square.and.arrow.up")
                    }
                    .disabled(!settings.isConfigured || isSharingLogs)
                } header: {
                    Text("Support")
                } footer: {
                    Text("The last two days of Oceano's logs, for support. Nothing is sent until you choose where.")
                        .foregroundStyle(Brand.muted)
                }

                UpdatesSection()

                Section {
                    Button {
                        showSwitchServer = true
                    } label: {
                        deviceCard
                    }
                    .buttonStyle(.plain)
                    Button {
                        showWifiSetup = true
                    } label: {
                        Label("Change Wi-Fi Network", systemImage: "wifi")
                    }
                    .disabled(!settings.isConfigured)
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
                    if let powerStatus {
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
        .sheet(isPresented: $showWifiSetup) {
            // Over the home network: the board opens its setup network,
            // which lets it take a new one.
            WifiSetupView(homeHost: settings.host)
        }
        .sheet(item: $sharedLog) { file in
            ShareSheet(file: file)
        }
        .task { await loadStreamingStatus() }
        .onAppear { Task { await updates.refresh() } }
    }

    private func loadStreamingStatus() async {
        guard settings.isConfigured else { return }
        do {
            let on = try await CatalogService(settings: settings).streamingExtras().extras.filter(\.enabled)
            streamingStatusText = on.isEmpty ? "Off" : on.map(\.name.title).joined(separator: ", ")
        } catch {
            streamingStatusText = "Unavailable"
        }
    }

    private func sendPower(_ action: PowerAction) async {
        isSendingPower = true
        defer { isSendingPower = false }
        powerStatus = nil
        let service = CatalogService(settings: settings)
        // The status is set inside the attempt, so a Retry that goes through shows it too.
        await messages.attempt {
            switch action {
            case .restart: try await service.rebootDevice()
            case .shutDown: try await service.powerOffDevice()
            }
            powerStatus = action.sentStatus
        }
    }

    /// "Preparing Logs…" and the share sheet come from inside the attempt, so the
    /// message's Retry shows both as the first try does.
    private func shareLogs() async {
        let service = CatalogService(settings: settings)
        await messages.attempt {
            isSharingLogs = true
            defer { isSharingLogs = false }
            sharedLog = SharedFile(url: try await downloadSupportLog(service))
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
