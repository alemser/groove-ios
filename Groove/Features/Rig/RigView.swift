import SwiftUI

/// Server connection plus everything hardware/back-office: stylus tracking,
/// the amplifier and remote (added in later phases), metadata enrichers, and
/// stack health. The catalog-management tabs (Library/History/Review) stay
/// lean; this is the hub for "how the rig is set up."
struct RigView: View {
    @Environment(AppSettings.self) private var settings

    @State private var host = ""
    @State private var port = "7073"
    @State private var scheme = "http"
    @State private var probe = ProbeState.idle
    @State private var saved = false

    @State private var enrichers: [EnricherSlot] = []
    @State private var enrichersError: String?

    @State private var stylusStatusText: String?
    @State private var ampStatusText: String?
    @State private var recognitionStatusText: String?

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

                Section("Hardware") {
                    NavigationLink {
                        StylusView()
                    } label: {
                        hardwareRow(
                            title: "Stylus Tracking",
                            subtitle: stylusStatusText ?? "Loading…",
                            icon: "gauge.with.dots.needle.33percent",
                            tint: Brand.gold
                        )
                    }
                    NavigationLink {
                        AmplifierView()
                    } label: {
                        hardwareRow(
                            title: "Amplifier",
                            subtitle: ampStatusText ?? "Loading…",
                            icon: "hifispeaker.and.homepod",
                            tint: Brand.teal
                        )
                    }
                    NavigationLink {
                        EquipmentRemoteView()
                    } label: {
                        hardwareRow(
                            title: "Equipment & Remote",
                            subtitle: "CD player and other IR devices",
                            icon: "appletvremote.gen4",
                            tint: Brand.muted
                        )
                    }
                }

                Section {
                    NavigationLink {
                        RecognitionProvidersScreen()
                    } label: {
                        hardwareRow(
                            title: "Recognition Providers",
                            subtitle: recognitionStatusText ?? "Loading…",
                            icon: "waveform.badge.magnifyingglass",
                            tint: Brand.gold
                        )
                    }
                } header: {
                    Text("Recognition")
                } footer: {
                    Text("What identifies a spinning record (ACRCloud, AudD, local fingerprints) — separate from the metadata enrichers below.")
                        .foregroundStyle(Brand.muted)
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
            .navigationTitle("Rig")
        }
        .onAppear(perform: loadFields)
        .task { await loadEnrichers() }
        .task { await loadStylusStatus() }
        .task { await loadAmpStatus() }
        .task { await loadRecognitionStatus() }
    }

    private func hardwareRow(title: String, subtitle: String, icon: String, tint: Color) -> some View {
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
            await loadStylusStatus()
            await loadAmpStatus()
            await loadRecognitionStatus()
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

    private func loadStylusStatus() async {
        guard settings.isConfigured else { return }
        do {
            let state = try await CatalogService(settings: settings).stylusState()
            guard let p = state.profile else {
                stylusStatusText = "Not configured"
                return
            }
            stylusStatusText = "\(p.brand) \(p.model) · \(String(format: "%.0f%% worn", state.metrics.wearPercent))"
        } catch {
            stylusStatusText = "Unavailable"
        }
    }

    private func loadAmpStatus() async {
        guard settings.isConfigured else { return }
        do {
            let snapshot = try await CatalogService(settings: settings).rigStatus()
            guard let amp = snapshot.amplifier else {
                ampStatusText = "Not configured"
                return
            }
            let device = [amp.maker, amp.model].compactMap { $0.nonEmpty }.joined(separator: " ")
            let power = (amp.power?.state ?? "unknown").replacingOccurrences(of: "_", with: " ").capitalized
            ampStatusText = device.isEmpty ? power : "\(device) · \(power)"
        } catch {
            ampStatusText = "Unavailable"
        }
    }

    private func loadRecognitionStatus() async {
        guard settings.isConfigured else { return }
        do {
            let state = try await CatalogService(settings: settings).recognitionProviders()
            let enabled = state.chain.filter(\.enabled).count
            recognitionStatusText = "\(enabled)/\(state.chain.count) enabled"
        } catch {
            recognitionStatusText = "Unavailable"
        }
    }
}
