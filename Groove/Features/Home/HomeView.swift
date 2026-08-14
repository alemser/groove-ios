import SwiftUI

/// Landing tab: connection health, a live Now Playing summary, and quick access
/// to what needs attention — the dashboard `groove-ios` didn't have before, in
/// the spirit of `oceano-player-ios`'s Home.
struct HomeView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(AttentionCenter.self) private var attention
    @Environment(NavigationState.self) private var navigation
    @Environment(NowPlayingModel.self) private var nowPlaying

    @State private var ampModel = AmplifierModel()
    @State private var equipmentModel = EquipmentRemoteModel()
    @State private var showRemoteSheet = false
    @State private var stylusState: StylusState?

    private var remoteAvailable: Bool {
        let ampLearned = ampModel.amplifierTarget?.actions.values.contains { $0.learned } ?? false
        let equipmentHasRemote = equipmentModel.equipment.contains { $0.hasRemote }
        return ampLearned || equipmentHasRemote
    }

    var body: some View {
        NavigationStack {
            List {
                if let error = nowPlaying.errorMessage {
                    connectionIssueSection(error)
                }
                nowPlayingSection
                if attention.autonomous {
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
            .grooveScreenBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    OceanoWordmark(fontSize: 26, weight: .bold)
                }
            }
        }
        .task { ampModel.configure(settings) }
        .task { equipmentModel.configure(settings) }
        .task { await loadStylusState() }
        .sheet(isPresented: $showRemoteSheet) {
            RemoteQuickAccessSheet(model: ampModel, equipmentModel: equipmentModel)
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

    // MARK: - Now Playing

    private var nowPlayingSection: some View {
        Section("Now Playing") {
            Button {
                navigation.openNowPlaying()
            } label: {
                if let pb = nowPlaying.status?.playback, pb.active || nowPlaying.isLikelyTransitioning() {
                    let recognizing = pb.isRecognizing || nowPlaying.isLikelyTransitioning()
                    HStack(spacing: 12) {
                        Artwork(raw: pb.artworkUrl, cornerRadius: 8, isRecognizing: recognizing)
                            .frame(width: 48, height: 48)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(pb.title?.nonEmpty ?? (recognizing ? "Recognizing…" : "Now Playing"))
                                .font(.headline)
                                .foregroundStyle(Brand.text)
                                .lineLimit(1)
                            Text(pb.artist?.nonEmpty ?? (recognizing ? "Listening…" : "Unknown artist"))
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

    /// Only shown once autonomous mode is on — mirrors the web nav's
    /// `studio-nav.js` gating (hides "Release matching", shows "Catalog
    /// session" once `GET /identity/recognition/providers` reports autonomous).
    private var sessionSection: some View {
        Section {
            NavigationLink {
                CatalogSessionView()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "waveform.circle")
                        .foregroundStyle(Brand.teal)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Catalog Session").foregroundStyle(Brand.text)
                        Text("Live view of this listening sitting").font(.caption).foregroundStyle(Brand.muted)
                    }
                    Spacer()
                }
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
                    Image(systemName: "appletvremote.gen4")
                        .foregroundStyle(Brand.accent)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Remote Control").foregroundStyle(Brand.text)
                        Text("Power, input, volume, and IR devices").font(.caption).foregroundStyle(Brand.muted)
                    }
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
                HStack(spacing: 12) {
                    Image(systemName: "gauge.with.dots.needle.33percent")
                        .foregroundStyle(Brand.gold)
                        .frame(width: 24)
                    if let profile = stylusState?.profile {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(profile.brand) \(profile.model)").foregroundStyle(Brand.text)
                            Text("\(Int((stylusState?.metrics.wearPercent ?? 0).rounded()))% worn")
                                .font(.caption)
                                .foregroundStyle(attention.rigAttentionCount > 0 ? Brand.warn : Brand.muted)
                        }
                    }
                    Spacer()
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
                Image(systemName: icon)
                    .foregroundStyle(Brand.accent)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundStyle(Brand.text)
                    Text(subtitle).font(.caption).foregroundStyle(Brand.muted)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Brand.muted)
            }
        }
        .buttonStyle(.plain)
    }
}
