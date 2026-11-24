import SwiftUI

/// Landing tab: connection health, a live Now Playing summary, and quick access
/// to what needs attention — the dashboard `groove-ios` didn't have before, in
/// the spirit of `oceano-player-ios`'s Home.
struct HomeView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(MessageCenter.self) private var messages
    @Environment(AttentionCenter.self) private var attention
    @Environment(NavigationState.self) private var navigation
    @Environment(NowPlayingModel.self) private var nowPlaying
    @Environment(\.scenePhase) private var scenePhase

    @State private var ampModel = AmplifierModel()
    @State private var equipmentModel = EquipmentRemoteModel()
    @State private var showRemoteSheet = false
    @State private var stylusState: StylusState?
    @State private var togglingRecognition = false

    private var remoteAvailable: Bool { ampModel.remoteAvailable(with: equipmentModel) }

    var body: some View {
        NavigationStack {
            List {
                if let error = nowPlaying.errorMessage {
                    connectionIssueSection(error)
                }
                if let checklist = setupChecklist {
                    setupSection(checklist)
                }
                nowPlayingSection
                if attention.offline {
                    sessionSection
                }
                if remoteAvailable {
                    remoteSection
                }
                if stylusState?.profile != nil {
                    stylusSection
                }
                if attention.count > 0 {
                    attentionSection
                }
                quickLinksSection
            }
            .scrollContentBackground(.hidden)
            .refreshable {
                await reloadRemote()
                await loadStylusState()
            }
            .grooveScreenBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    OceanoWordmark(fontSize: 26, weight: .bold)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    recognitionPauseButton
                }
            }
        }
        .task { ampModel.configure(settings, messages: messages) }
        .task { equipmentModel.configure(settings, messages: messages) }
        .task { await loadStylusState() }
        .task { await retryRemoteWhileMissing() }
        // Back from Recognition Providers, the setup card reads the new choice at once.
        .onAppear { Task { await attention.refresh() } }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await reloadRemote() }
        }
        .sheet(isPresented: $showRemoteSheet) {
            RemoteQuickAccessSheet(model: ampModel, equipmentModel: equipmentModel)
        }
    }

    /// The Remote section shows only once the rig's state has loaded. It used
    /// to load once, when Home first appeared, so a failed first fetch (oceano
    /// restarting, the network not up yet) hid the section until the app was
    /// killed. It now reloads on returning to the foreground and on pull to
    /// refresh, and retries while nothing has loaded.
    private func reloadRemote() async {
        async let amp: Void = ampModel.load()
        async let equipment: Void = equipmentModel.load()
        _ = await (amp, equipment)
    }

    private func retryRemoteWhileMissing() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(15))
            guard !Task.isCancelled, ampModel.snapshot == nil, equipmentModel.equipment.isEmpty else { return }
            await reloadRemote()
        }
    }

    private func loadStylusState() async {
        guard settings.isConfigured else { return }
        stylusState = try? await CatalogService(settings: settings).stylusState()
    }

    // MARK: - Connection

    /// A working connection isn't worth a card — this only appears when
    /// there's actually a problem to act on.
    private func connectionIssueSection(_ error: String) -> some View {
        Section {
            HStack(spacing: 8) {
                Image(systemName: "wifi.exclamationmark")
                    .foregroundStyle(Brand.warn)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Connection issue").font(.subheadline).foregroundStyle(Brand.text)
                    Text(error).font(.caption).foregroundStyle(Brand.muted)
                }
            }
        }
    }

    // MARK: - Finish setting up

    /// What's left to set up after connecting; nil once it's done or the optional rest is put off.
    private var setupChecklist: SetupChecklist? {
        guard let checklist = SetupChecklist.of(status: nowPlaying.status, recognitionChosen: attention.recognitionChosen),
              checklist.isShown(recognitionPutOff: settings.recognitionSetupPutOff) else { return nil }
        return checklist
    }

    private func setupSection(_ checklist: SetupChecklist) -> some View {
        Section {
            NavigationLink {
                EnricherSettingsView()
            } label: {
                setupStep(
                    .metadataEnrichers,
                    toDo: "Required: finds each record's album, artwork and tracklist",
                    done: checklist.enrichersReady
                )
            }
            NavigationLink {
                RecognitionProvidersScreen()
            } label: {
                setupStep(
                    .recognitionProviders,
                    toDo: "Optional: names records Oceano hasn't learned yet",
                    done: checklist.recognitionChosen
                )
            }
        } header: {
            Text("Finish Setting Up")
        } footer: {
            if checklist.canPutOff {
                HStack {
                    Spacer()
                    Button("Not Now") { settings.recognitionSetupPutOff = true }
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Brand.muted)
                }
            }
        }
    }

    /// One setup step: what it's for while it's to do, a check once done. Either way it opens its screen.
    private func setupStep(_ entry: ScreenEntry, toDo: String, done: Bool) -> some View {
        IconRow(
            title: entry.title,
            subtitle: done ? "Done" : toDo,
            icon: done ? "checkmark.circle.fill" : entry.icon,
            tint: done ? Brand.ok : entry.tint
        )
    }

    // MARK: - Recognition pause

    /// Discreet top-of-Home quick toggle for "pause recognition, listen
    /// freely / stop the noise on the kiosk when an album won't match" — the
    /// use case doesn't fit burying this in Settings, unlike Offline Mode.
    private var recognitionPauseButton: some View {
        Button {
            guard !togglingRecognition else { return }
            togglingRecognition = true
            Task {
                await attention.setSuspended(!attention.suspended)
                togglingRecognition = false
            }
        } label: {
            Image(systemName: attention.suspended ? "waveform.slash" : "waveform")
                .foregroundStyle(attention.suspended ? Brand.warn : Brand.muted)
        }
        .disabled(togglingRecognition)
        .accessibilityLabel(attention.suspended ? "Resume recognition" : "Pause recognition")
    }

    // MARK: - Now Playing

    private var nowPlayingSection: some View {
        Section("Now Playing") {
            Button {
                navigation.openNowPlaying()
            } label: {
                if let s = nowPlaying.summary {
                    HStack(spacing: 12) {
                        Artwork(raw: s.artworkUrl, cornerRadius: 8, isRecognizing: s.isRecognizing)
                            .frame(width: 48, height: 48)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(s.title)
                                .font(.headline)
                                .foregroundStyle(Brand.text)
                                .lineLimit(1)
                            Text(s.subtitle)
                                .font(.subheadline)
                                .foregroundStyle(Brand.muted)
                                .lineLimit(1)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Brand.muted)
                    }
                } else {
                    Label("Nothing playing", systemImage: "opticaldisc")
                        .foregroundStyle(Brand.muted)
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the full Now Playing screen")
        }
    }

    // MARK: - Catalog session

    /// Only shown once offline mode is on — mirrors the web nav's
    /// `studio-nav.js` gating (hides "Release matching", shows "Catalog
    /// session" once `GET /identity/recognition/providers` reports offline).
    private var sessionSection: some View {
        Section {
            NavigationLink {
                CatalogSessionView()
            } label: {
                IconRow(
                    title: "Catalog Session",
                    subtitle: "Live view of this listening sitting",
                    icon: "waveform.circle",
                    tint: Brand.teal
                )
            }
            .accessibilityHint("Opens the live catalog session dashboard")
        }
    }

    // MARK: - Remote

    private var remoteSection: some View {
        Section("Remote") {
            Button {
                showRemoteSheet = true
            } label: {
                HStack(spacing: 12) {
                    IconRow(title: "Remote Control", subtitle: "Power, input, volume, and IR devices", icon: "appletvremote.gen4")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Brand.muted)
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the remote control")
        }
    }

    // MARK: - Stylus

    private var stylusSection: some View {
        Section("Stylus") {
            NavigationLink {
                StylusView()
            } label: {
                if let profile = stylusState?.profile {
                    IconRow(
                        title: "\(profile.brand) \(profile.model)",
                        subtitle: "\(Int((stylusState?.metrics.wearPercent ?? 0).rounded()))% worn",
                        icon: "gauge.with.dots.needle.33percent",
                        tint: Brand.gold,
                        subtitleColor: attention.rigAttentionCount > 0 ? Brand.warn : Brand.muted
                    )
                }
            }
            .accessibilityHint("Opens stylus tracking")
        }
    }

    // MARK: - Attention

    private var attentionSection: some View {
        Section {
            Button {
                navigation.selectedTab = .library
            } label: {
                HStack {
                    Label(
                        "\(attention.count) item\(attention.count == 1 ? "" : "s") need review",
                        systemImage: "checkmark.seal"
                    )
                    .foregroundStyle(Brand.text)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Brand.muted)
                }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Quick links

    private var quickLinksSection: some View {
        Section("Quick Links") {
            quickLink(title: "Library", subtitle: "Browse your albums", icon: "square.stack") {
                navigation.selectedTab = .library
            }
            quickLink(title: "Rig", subtitle: "Stylus and amplifier", icon: "hifispeaker.and.homepod") {
                navigation.selectedTab = .rig
            }
            quickLink(title: "Settings", subtitle: "Catalog server, recognition & enrichers, stack health", icon: "gearshape") {
                navigation.selectedTab = .settings
            }
        }
    }

    private func quickLink(title: String, subtitle: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                IconRow(title: title, subtitle: subtitle, icon: icon)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Brand.muted)
            }
        }
        .buttonStyle(.plain)
    }
}
