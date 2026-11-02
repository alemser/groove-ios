import SwiftUI

/// Physical hardware: stylus tracking, audio input and streaming, and the
/// rig — the amplifier, the equipment around it and the IR bridge that
/// controls them — behind the "Rig" switch (off on a new installation).
/// Catalog server connection and recognition/enrichment config live in
/// Settings, not here.
struct RigView: View {
    @Environment(AppSettings.self) private var settings

    @State private var stylusStatusText: String?
    @State private var ampStatusText: String?
    @State private var bridgeStatusText: String?
    @State private var streamingStatusText: String?
    @State private var audioInputStatusText: String?
    @State private var rulesStatusText: String?
    /// The "Rig" switch; nil until loaded.
    @State private var rigEnabled: Bool?
    @State private var rigSwitchError: String?

    var body: some View {
        NavigationStack {
            Form {
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
                        AudioInputView()
                    } label: {
                        hardwareRow(
                            title: "Audio Input",
                            subtitle: audioInputStatusText ?? "Loading…",
                            icon: "waveform",
                            tint: Brand.teal
                        )
                    }
                    NavigationLink {
                        StreamingView()
                    } label: {
                        hardwareRow(
                            title: "Streaming",
                            subtitle: streamingStatusText ?? "Loading…",
                            icon: "airplayaudio",
                            tint: Brand.ok
                        )
                    }
                }

                Section {
                    Toggle("Rig", isOn: Binding(
                        get: { rigEnabled ?? false },
                        set: { on in Task { await setRig(on) } }
                    ))
                    .disabled(rigEnabled == nil)
                    if rigEnabled == true {
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
                            IRBridgeView()
                        } label: {
                            hardwareRow(
                                title: "IR Bridge",
                                subtitle: bridgeStatusText ?? "Loading…",
                                icon: "dot.radiowaves.left.and.right",
                                tint: Brand.gold
                            )
                        }
                    }
                } footer: {
                    Text(rigSwitchError ?? "Your amplifier, the equipment around it, and the IR bridge that lets Oceano control them. Off, Oceano still recognises what plays, shows it and streams.")
                        .foregroundStyle(rigSwitchError == nil ? Brand.muted : Brand.err)
                }

                if rigEnabled == true {
                    Section("Automations") {
                        NavigationLink {
                            RulesView()
                        } label: {
                            hardwareRow(
                                title: "Rules",
                                subtitle: rulesStatusText ?? "Loading…",
                                icon: "wand.and.stars",
                                tint: Brand.gold
                            )
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .grooveScreenBackground()
            .navigationTitle("Rig")
        }
        .task { await loadStylusStatus() }
        .task { await loadRig() }
        .task { await loadStreamingStatus() }
        .task { await loadAudioInputStatus() }
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

    /// The switch, then — while it's on — the rig's own rows.
    private func loadRig() async {
        guard settings.isConfigured else { return }
        do {
            rigEnabled = try await CatalogService(settings: settings).rigControl().enabled
        } catch {
            // An older groove-rig has no switch: its rig is always on.
            rigEnabled = true
        }
        guard rigEnabled == true else { return }
        async let amp: Void = loadAmpStatus()
        async let rules: Void = loadRulesStatus()
        _ = await (amp, rules)
    }

    private func setRig(_ on: Bool) async {
        let previous = rigEnabled
        rigEnabled = on
        do {
            try await CatalogService(settings: settings).rigSetControl(enabled: on)
            rigSwitchError = nil
            await loadRig()
        } catch {
            rigEnabled = previous
            rigSwitchError = error.localizedForDisplay
        }
    }

    private func loadAmpStatus() async {
        do {
            let snapshot = try await CatalogService(settings: settings).rigStatus()
            bridgeStatusText = snapshot.irBridgePaired ? "Paired" : "Not paired"
            guard let amp = snapshot.amplifier else {
                ampStatusText = "Not set up"
                return
            }
            let device = [amp.maker, amp.model].compactMap { $0.nonEmpty }.joined(separator: " ")
            let power = (amp.power?.state ?? "unknown").replacingOccurrences(of: "_", with: " ").capitalized
            ampStatusText = device.isEmpty ? power : "\(device) · \(power)"
        } catch {
            ampStatusText = "Unavailable"
            bridgeStatusText = "Unavailable"
        }
    }

    private func loadStreamingStatus() async {
        guard settings.isConfigured else { return }
        do {
            let response = try await CatalogService(settings: settings).rigAudioOutputs()
            let label = response.outputs.first { $0.id == response.selected }?.label
            streamingStatusText = label ?? "Not set"
        } catch {
            streamingStatusText = "Unavailable"
        }
    }

    /// On a variable line out the band is the headline — a persistently low
    /// level should be visible here without opening the screen.
    private func loadAudioInputStatus() async {
        guard settings.isConfigured else { return }
        do {
            let level = try await CatalogService(settings: settings).rigCaptureLevel()
            switch level.inputLevel {
            case .fixed:
                audioInputStatusText = "Fixed level (REC OUT)"
            case .variable:
                // The meter also reads silence; only a band measured over
                // music says anything about the calibration.
                let band = level.programme.band
                audioInputStatusText = band == .unknown || !level.isPlaying
                    ? "Variable line out"
                    : "Variable line out · Level \(band.title.lowercased())"
            }
        } catch {
            audioInputStatusText = "Unavailable"
        }
    }

    private func loadRulesStatus() async {
        do {
            let rules = try await CatalogService(settings: settings).rigRules().items
            let on = rules.filter(\.enabled)
            if on.isEmpty {
                rulesStatusText = rules.isEmpty ? "None" : "All off"
            } else if on.contains(where: { !$0.available }) {
                rulesStatusText = "\(on.count) on · needs setup"
            } else {
                rulesStatusText = "\(on.count) on"
            }
        } catch {
            rulesStatusText = "Unavailable"
        }
    }
}

// MARK: - IR bridge

/// The IR bridge: what it is, whether it's paired, and pairing it — found
/// by a network search, or by its address as a fallback. Never named by
/// brand.
struct IRBridgeView: View {
    @Environment(AppSettings.self) private var settings
    @State private var model = IRBridgeModel()
    @State private var manualHost = ""

    var body: some View {
        Form {
            Section {
                Text("An IR bridge is a small Wi-Fi device that sends your remotes' infrared signals. With one, Oceano can switch your amplifier on, change its input and control your other equipment. Place it where it can see them, connect it to your Wi-Fi with its own app, then pair it here.")
                    .font(.subheadline)
                    .foregroundStyle(Brand.muted)
            }

            if let bridge = model.bridge {
                Section("Status") {
                    InfoRow(label: "Bridge", value: statusText(bridge))
                }

                if bridge.capabilities?.discover == true {
                    Section {
                        Button {
                            Task { await model.search() }
                        } label: {
                            HStack {
                                Text(model.isSearching ? "Searching…" : (bridge.isPaired ? "Search Again" : "Search for Bridges"))
                                if model.isSearching {
                                    Spacer()
                                    ProgressView()
                                }
                            }
                        }
                        .disabled(model.isSearching || model.pairingHost != nil)
                        ForEach(model.found) { found in
                            foundRow(found, bridge: bridge)
                        }
                    } footer: {
                        if let note = model.searchNote {
                            Text(note).foregroundStyle(Brand.muted)
                        }
                    }
                }

                if bridge.capabilities?.pair == true {
                    Section {
                        TextField("IP address", text: $manualHost)
                            .keyboardType(.decimalPad)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button(model.pairingHost == manualHost.trimmingCharacters(in: .whitespaces) ? "Pairing…" : "Pair") {
                            Task { await model.pair(host: manualHost.trimmingCharacters(in: .whitespaces)) }
                        }
                        .disabled(manualHost.trimmingCharacters(in: .whitespaces).isEmpty || model.pairingHost != nil)
                    } header: {
                        Text("Pair by Address")
                    } footer: {
                        Text("If the search doesn't find it, its address is shown in its own app.")
                            .foregroundStyle(Brand.muted)
                    }
                }
            } else if model.isLoading {
                Section { ProgressView() }
            }

            if let error = model.error {
                Section { Text(error).foregroundStyle(Brand.err) }
            }
        }
        .scrollContentBackground(.hidden)
        .grooveScreenBackground()
        .navigationTitle("IR Bridge")
        .navigationBarTitleDisplayMode(.inline)
        .task { model.configure(settings) }
    }

    private func statusText(_ bridge: RigBackend) -> String {
        guard bridge.isPaired else { return "Not paired" }
        let host = bridge.host?.nonEmpty.map { " · \($0)" } ?? ""
        return (bridge.healthy ? "Paired" : "Paired, not reachable") + host
    }

    @ViewBuilder
    private func foundRow(_ found: RigDiscoveredBridge, bridge: RigBackend) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(found.name?.nonEmpty ?? found.model?.nonEmpty ?? "IR bridge")
                    .foregroundStyle(Brand.text)
                Text([found.name?.nonEmpty != nil ? found.model?.nonEmpty : nil, found.host].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(Brand.muted)
            }
            Spacer()
            if bridge.isPaired, bridge.host == found.host {
                Text("Paired").font(.caption).foregroundStyle(Brand.ok)
            } else if found.locked {
                Text("Locked — unlock it in its app").font(.caption).foregroundStyle(Brand.warn)
            } else {
                Button(model.pairingHost == found.host ? "Pairing…" : "Pair") {
                    Task { await model.pair(host: found.host) }
                }
                .buttonStyle(.bordered)
                .disabled(model.pairingHost != nil)
            }
        }
    }
}

@MainActor
@Observable
final class IRBridgeModel {
    /// The installation's one bridge (groove-rig never adds or removes one).
    var bridge: RigBackend?
    var found: [RigDiscoveredBridge] = []
    var isLoading = true
    var isSearching = false
    /// What the last search came to, when it has something to say.
    var searchNote: String?
    /// The host a pairing is running for.
    var pairingHost: String?
    var error: String?

    private var settings: AppSettings?

    /// How long pairing may take before the screen gives up waiting.
    /// Chosen: a pair session is one hello + auth exchange (~0.2 s on
    /// oceano, measured for groove-rig's bridge script) plus starting the
    /// bridge process, so 20 s only bounds a lost session.
    private static let pairWait: Duration = .seconds(20)
    /// Between session polls — the same cadence as LearnSessionModel.
    private static let pollInterval: Duration = .milliseconds(500)

    func configure(_ settings: AppSettings) {
        if self.settings == nil {
            self.settings = settings
            Task { await load() }
        }
    }

    func load() async {
        guard let settings else { return }
        do {
            bridge = try await CatalogService(settings: settings).rigBackends().first
            error = nil
        } catch {
            self.error = error.localizedForDisplay
        }
        isLoading = false
    }

    func search() async {
        guard let settings, let bridge else { return }
        isSearching = true
        searchNote = nil
        defer { isSearching = false }
        do {
            found = try await CatalogService(settings: settings).rigDiscoverBridges(backendId: bridge.id)
            error = nil
            if found.isEmpty {
                searchNote = "No IR bridge answered. Check that it is powered on and connected to the same Wi-Fi as Oceano, then search again."
            }
        } catch {
            self.error = error.localizedForDisplay
        }
    }

    func pair(host: String) async {
        guard let settings, let bridge, !host.isEmpty else { return }
        pairingHost = host
        defer { pairingHost = nil }
        let service = CatalogService(settings: settings)
        do {
            let started = try await service.rigStartPair(backendId: bridge.id, host: host)
            let deadline = ContinuousClock.now + Self.pairWait
            var session = started
            while session.status != "success", session.status != "failed", ContinuousClock.now < deadline {
                try await Task.sleep(for: Self.pollInterval)
                session = try await service.rigSession(id: started.id)
            }
            switch session.status {
            case "success":
                error = nil
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            case "failed":
                error = session.message?.nonEmpty ?? "Pairing failed."
            default:
                error = "The bridge didn't answer. Check its address and that it's on the same Wi-Fi."
            }
        } catch {
            self.error = error.localizedForDisplay
        }
        await load()
    }
}
