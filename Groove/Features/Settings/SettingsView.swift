import SwiftUI

/// App-level settings: catalog server connection and recognition/enrichment
/// configuration. Rig stays focused on physical hardware; this is everything
/// else about how the app is wired up.
struct SettingsView: View {
    @Environment(AppSettings.self) private var settings

    @State private var showSwitchServer = false
    @State private var showBLEProvisioning = false

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
