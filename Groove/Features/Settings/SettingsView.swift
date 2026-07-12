import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings

    @State private var host = ""
    @State private var port = "7073"
    @State private var scheme = "http"
    @State private var probe = ProbeState.idle
    @State private var saved = false

    @State private var enrichers: [EnricherSlot] = []
    @State private var enrichersError: String?

    var body: some View {
        NavigationStack {
            Form {
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

                Section("Metadata Enrichers") {
                    if let enrichersError {
                        Text(enrichersError).font(.footnote).foregroundStyle(Brand.muted)
                    } else if enrichers.isEmpty {
                        Text("Loading…").font(.footnote).foregroundStyle(Brand.muted)
                    } else {
                        ForEach(enrichers) { slot in
                            enricherRow(slot)
                        }
                    }
                }

                Section {
                    NavigationLink {
                        HealthView()
                    } label: {
                        Label("Stack Health", systemImage: "heart.text.square")
                    }
                }

                Section {
                    Button(role: .destructive) {
                        settings.host = ""
                    } label: {
                        Label("Disconnect", systemImage: "wifi.slash")
                    }
                } footer: {
                    Text("Groove \(appVersion)")
                }
            }
            .scrollContentBackground(.hidden)
            .grooveScreenBackground()
            .navigationTitle("Settings")
        }
        .onAppear(perform: loadFields)
        .task { await loadEnrichers() }
    }

    private func enricherRow(_ slot: EnricherSlot) -> some View {
        Toggle(isOn: Binding(
            get: { slot.enabled },
            set: { newValue in Task { await toggleEnricher(slot, enabled: newValue) } }
        )) {
            VStack(alignment: .leading, spacing: 2) {
                Text(slot.displayName ?? slot.id.capitalized)
                    .foregroundStyle(Brand.text)
                Text(slot.configured ? "Configured" : "No credentials")
                    .font(.caption)
                    .foregroundStyle(slot.configured ? Brand.ok : Brand.muted)
            }
        }
        .tint(Brand.accent)
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
            await loadEnrichers()
        } catch {
            probe = .failed((error as? APIError)?.localizedDescription ?? error.localizedDescription)
        }
    }

    private func loadEnrichers() async {
        guard settings.isConfigured else { return }
        do {
            enrichers = try await CatalogService(settings: settings).enrichers().chain
            enrichersError = nil
        } catch {
            enrichersError = "Enrichers unavailable."
        }
    }

    private func toggleEnricher(_ slot: EnricherSlot, enabled: Bool) async {
        do {
            try await CatalogService(settings: settings).setEnricherEnabled(id: slot.id, enabled: enabled)
            await loadEnrichers()
        } catch {
            await loadEnrichers()
        }
    }
}
