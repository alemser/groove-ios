import SwiftUI

/// First-run screen: point the app at a groove-catalog server. Leads with
/// Bonjour discovery — a pulsing radar animation while searching, then the
/// found server(s) as one-tap cards — and tucks manual host/IP entry behind
/// a fallback link instead of showing input fields by default.
struct ConnectView: View {
    @Environment(AppSettings.self) private var settings

    @State private var host = ""
    @State private var port = "7073"
    @State private var scheme = "http"
    @State private var probe = ProbeState.idle
    @State private var discovery = CatalogDiscovery()
    @State private var showManualEntry = false
    @State private var showSlowHint = false
    @State private var autoConnectAttemptedIDs: Set<String> = []

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                header

                if showManualEntry {
                    form
                    connectButton
                } else if discovery.hosts.isEmpty {
                    searchingState
                } else {
                    discoveredHosts
                }

                if case let .failed(message) = probe {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(Brand.err)
                        .multilineTextAlignment(.center)
                }

                if showManualEntry || !discovery.hosts.isEmpty {
                    manualEntryToggle
                }
            }
            .padding(24)
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity)
        }
        .grooveScreenBackground()
        .task { discovery.startBrowsing() }
        .onDisappear { discovery.stopBrowsing() }
        .task {
            try? await Task.sleep(for: .seconds(3))
            guard discovery.hosts.isEmpty, !showManualEntry else { return }
            withAnimation { showSlowHint = true }
        }
        .animation(.easeInOut(duration: 0.3), value: showManualEntry)
        .animation(.easeInOut(duration: 0.3), value: discovery.hosts.isEmpty)
        .onChange(of: discovery.hosts) { _, hosts in
            // Every listed host already answered /status as a groove-catalog,
            // so when there's exactly one there is nothing left to choose —
            // connect without waiting for a tap. One attempt per host: if it
            // fails (or a second server appears) the user decides.
            guard !showManualEntry, !probe.isProbing,
                  hosts.count == 1, let only = hosts.first,
                  !autoConnectAttemptedIDs.contains(only.id) else { return }
            autoConnectAttemptedIDs.insert(only.id)
            select(only)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 12) {
            if showManualEntry || !discovery.hosts.isEmpty {
                ZStack {
                    Circle().fill(Brand.teal.opacity(0.12)).frame(width: 96, height: 96)
                    Image(systemName: "opticaldisc.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(Brand.teal)
                }
            } else {
                RadarPulse()
            }
            OceanoWordmark(fontSize: 34, weight: .bold)
            Text("Your library, in your pocket")
                .font(.subheadline)
                .foregroundStyle(Brand.muted)
        }
        .padding(.top, 24)
    }

    // MARK: - Searching state

    private var searchingState: some View {
        VStack(spacing: 20) {
            VStack(spacing: 10) {
                Text("Looking for your Oceano…")
                    .font(.headline)
                    .foregroundStyle(Brand.text)
                Text("Make sure your phone and the Oceano server are on the same Wi-Fi.")
                    .font(.subheadline)
                    .foregroundStyle(Brand.muted)
                    .multilineTextAlignment(.center)
            }

            if showSlowHint {
                VStack(spacing: 12) {
                    Text("Couldn't find it automatically — some networks block device discovery between phones and other devices.")
                        .font(.footnote)
                        .foregroundStyle(Brand.muted)
                        .multilineTextAlignment(.center)
                    Button {
                        showManualEntry = true
                    } label: {
                        Label("Enter Server Manually", systemImage: "keyboard")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Brand.accent)
                    .controlSize(.large)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 8)
    }

    // MARK: - Discovered hosts

    private var discoveredHosts: some View {
        VStack(spacing: 14) {
            Text("Found on your network")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Brand.muted)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(discovery.hosts) { discovered in
                    Button {
                        select(discovered)
                    } label: {
                        HStack(spacing: 14) {
                            ZStack {
                                Circle().fill(Brand.teal.opacity(0.15)).frame(width: 44, height: 44)
                                Image(systemName: "server.rack")
                                    .foregroundStyle(Brand.teal)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(discovered.displayName)
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(Brand.text)
                                Text("\(discovered.host):\(discovered.port)")
                                    .font(.caption)
                                    .foregroundStyle(Brand.muted)
                            }
                            Spacer()
                            if probe.isProbing {
                                ProgressView().tint(Brand.muted)
                            } else {
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Brand.muted)
                            }
                        }
                        .padding(16)
                    }
                    .buttonStyle(.plain)
                    .disabled(probe.isProbing)
                    if discovered.id != discovery.hosts.last?.id {
                        Divider().overlay(Brand.border).padding(.leading, 16)
                    }
                }
            }
            .grooveCard()
        }
    }

    private func select(_ discovered: DiscoveredCatalogHost) {
        host = discovered.host
        port = String(discovered.port)
        scheme = "http"
        Task { await connect() }
    }

    // MARK: - Manual entry

    private var manualEntryToggle: some View {
        Button {
            showManualEntry.toggle()
        } label: {
            Text(showManualEntry ? "Search Automatically Instead" : "Enter Server Manually")
                .font(.footnote.weight(.medium))
                .foregroundStyle(Brand.muted)
        }
        .buttonStyle(.plain)
    }

    private var form: some View {
        VStack(spacing: 0) {
            ConnectionFields(host: $host, port: $port, scheme: $scheme)
        }
        .grooveCard()
    }

    private var connectButton: some View {
        Button {
            Task { await connect() }
        } label: {
            HStack {
                if probe.isProbing { ProgressView().tint(Brand.bg) }
                Text(probe.isProbing ? "Connecting…" : "Connect")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(Brand.accent)
        .controlSize(.large)
        .disabled(host.trimmingCharacters(in: .whitespaces).isEmpty || probe.isProbing)
    }

    private func connect() async {
        probe = .probing
        let trial = AppSettings()
        trial.host = host.trimmingCharacters(in: .whitespaces)
        trial.port = Int(port) ?? 7073
        trial.scheme = scheme
        do {
            _ = try await CatalogService(settings: trial).status()
            settings.host = trial.host
            settings.port = trial.port
            settings.scheme = trial.scheme
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            probe = .idle
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            probe = .failed((error as? APIError)?.localizedDescription ?? error.localizedDescription)
        }
    }
}

/// Three staggered rings pulsing outward from the app icon glyph, signaling
/// "actively searching" the way Find My / AirDrop's radar does.
private struct RadarPulse: View {
    @State private var animate = false

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .stroke(Brand.teal.opacity(0.5), lineWidth: 1.5)
                    .frame(width: 96, height: 96)
                    .scaleEffect(animate ? 1.7 : 0.5)
                    .opacity(animate ? 0 : 0.7)
                    .animation(
                        .easeOut(duration: 1.8)
                            .repeatForever(autoreverses: false)
                            .delay(Double(i) * 0.5),
                        value: animate
                    )
            }
            Circle().fill(Brand.teal.opacity(0.12)).frame(width: 96, height: 96)
            Image(systemName: "opticaldisc.fill")
                .font(.system(size: 44))
                .foregroundStyle(Brand.teal)
        }
        .frame(width: 160, height: 120)
        .onAppear { animate = true }
        .accessibilityLabel("Searching for your Oceano server")
    }
}

/// Reusable host/port/scheme fields.
struct ConnectionFields: View {
    @Binding var host: String
    @Binding var port: String
    @Binding var scheme: String

    var body: some View {
        VStack(spacing: 0) {
            field {
                TextField("Host or IP (e.g. 192.168.1.20)", text: $host)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
            }
            Divider().overlay(Brand.border)
            field {
                TextField("Port", text: $port)
                    .keyboardType(.numberPad)
            }
            Divider().overlay(Brand.border)
            field {
                Picker("Scheme", selection: $scheme) {
                    Text("http").tag("http")
                    Text("https").tag("https")
                }
                .pickerStyle(.segmented)
            }
        }
    }

    private func field<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .foregroundStyle(Brand.text)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
    }
}

enum ProbeState {
    case idle, probing, failed(String)
    var isProbing: Bool { if case .probing = self { return true }; return false }
}
