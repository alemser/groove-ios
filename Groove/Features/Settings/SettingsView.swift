import SwiftUI

/// App-level settings: catalog server connection and recognition/enrichment
/// configuration. Rig stays focused on physical hardware; this is everything
/// else about how the app is wired up.
struct SettingsView: View {
    @Environment(AppSettings.self) private var settings

    @State private var host = ""
    @State private var port = "7073"
    @State private var scheme = "http"
    @State private var probe = ProbeState.idle
    @State private var saved = false

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

                Section("Catalog Server") {
                    TextField("Host or IP", text: $host)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    TextField("Port", text: $port)
                        .keyboardType(.numberPad)
                    Picker("Scheme", selection: $scheme) {
                        Text("http").tag("http")
                        Text("https").tag("https")
                    }
                }

                Section {
                    Button {
                        Task { await testAndSave() }
                    } label: {
                        HStack {
                            if probe.isProbing { ProgressView() }
                            Text(probe.isProbing ? "Testing…" : "Test & Save")
                            Spacer()
                            if saved { Image(systemName: "checkmark.circle.fill").foregroundStyle(Brand.ok) }
                        }
                    }
                    .disabled(probe.isProbing)
                } footer: {
                    if case let .failed(message) = probe {
                        Text(message).foregroundStyle(Brand.err)
                    } else if let url = settings.baseURL {
                        Text("Connected to \(url.absoluteString)")
                    }
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
        .onAppear(perform: loadFields)
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

    private func loadFields() {
        host = settings.host
        port = String(settings.port)
        scheme = settings.scheme
    }

    private func testAndSave() async {
        probe = .probing
        saved = false
        let trial = AppSettings()
        trial.host = host.trimmingCharacters(in: .whitespaces)
        trial.port = Int(port) ?? 7073
        trial.scheme = scheme
        do {
            _ = try await CatalogService(settings: trial).status()
            settings.host = trial.host
            settings.port = trial.port
            settings.scheme = trial.scheme
            probe = .idle
            saved = true
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            probe = .failed((error as? APIError)?.localizedDescription ?? error.localizedDescription)
        }
    }
}
