import SwiftUI

/// Guided BLE onboarding: find a nearby, unconfigured Oceano device, pick a
/// WiFi network, enter its password, and watch it join. Once connected, the
/// device drops its BLE advertisement and starts advertising over mDNS
/// instead — `onConnected` hands off to `ConnectView`'s existing discovery
/// rather than hardcoding the host.
struct BLEProvisioningView: View {
    var onConnected: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @State private var model = BLEProvisioningModel()
    @State private var password = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                content
                // TEMPORARY diagnostic panel (2026-09-02, Phase 2 first
                // field test) — remove once confirmed working.
                if !model.debugLog.isEmpty {
                    debugPanel
                }
            }
            .grooveScreenBackground()
            .navigationTitle("Set Up Oceano")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        model.cancel()
                        dismiss()
                    }
                }
            }
        }
        .task {
            model.start()
        }
    }

    private var debugPanel: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(model.debugLog.enumerated()), id: \.offset) { index, line in
                        Text(line)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Brand.muted)
                            .id(index)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
            }
            .frame(height: 160)
            .background(Brand.card)
            .onChange(of: model.debugLog.count) { _, newCount in
                proxy.scrollTo(newCount - 1, anchor: .bottom)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .searching:
            statusScreen(
                icon: { ProgressView().controlSize(.large).tint(Brand.accent) },
                title: "Looking for your Oceano device…",
                subtitle: "Make sure it's powered on and hasn't already joined a network."
            )
        case .pickingNetwork:
            networkList
        case let .enteringPassword(network):
            passwordForm(network)
        case let .applying(ssid):
            statusScreen(
                icon: { ProgressView().controlSize(.large).tint(Brand.accent) },
                title: "Connecting to “\(ssid)”…",
                subtitle: "This can take a few seconds."
            )
        case let .success(ssid, ip):
            statusScreen(
                icon: {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(Brand.ok)
                },
                title: "Connected!",
                subtitle: "Oceano joined “\(ssid)”\(ip.isEmpty ? "" : " at \(ip)").",
                footer: {
                    Button("Done") {
                        onConnected()
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Brand.accent)
                    .controlSize(.large)
                }
            )
        case let .failed(message):
            statusScreen(
                icon: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(Brand.err)
                },
                title: "Couldn't set up Oceano",
                subtitle: message,
                footer: {
                    Button("Try Again") { model.retry() }
                        .buttonStyle(.borderedProminent)
                        .tint(Brand.accent)
                        .controlSize(.large)
                }
            )
        }
    }

    // MARK: - Network list

    private var networkList: some View {
        ScrollView {
            VStack(spacing: 14) {
                Text("Choose a WiFi network")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Brand.muted)
                if model.networks.isEmpty {
                    VStack(spacing: 12) {
                        ProgressView().tint(Brand.muted)
                        Text("Scanning for nearby networks…")
                            .font(.footnote)
                            .foregroundStyle(Brand.muted)
                    }
                    .padding(.top, 40)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(model.networks) { network in
                            Button {
                                model.selectNetwork(network)
                            } label: {
                                networkRow(network)
                            }
                            .buttonStyle(.plain)
                            if network.id != model.networks.last?.id {
                                Divider().overlay(Brand.border).padding(.leading, 16)
                            }
                        }
                    }
                    .grooveCard()
                }
                Button("Rescan") { model.rescan() }
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Brand.muted)
                    .padding(.top, 4)
            }
            .padding(24)
        }
    }

    private func networkRow(_ network: BLEWiFiNetwork) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "wifi")
                .foregroundStyle(Brand.teal)
                .frame(width: 24)
            Text(network.ssid)
                .foregroundStyle(Brand.text)
            Spacer()
            if network.secure {
                Image(systemName: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(Brand.muted)
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Brand.muted)
        }
        .padding(16)
    }

    // MARK: - Password entry

    private func passwordForm(_ network: BLEWiFiNetwork) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 8) {
                    Image(systemName: "wifi.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(Brand.teal)
                    Text(network.ssid)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Brand.text)
                }
                .padding(.top, 24)

                if network.secure {
                    VStack(spacing: 0) {
                        SecureField("Password", text: $password)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(16)
                            .foregroundStyle(Brand.text)
                    }
                    .grooveCard()
                } else {
                    Text("This network is open — no password needed.")
                        .font(.footnote)
                        .foregroundStyle(Brand.muted)
                }

                Button("Connect") {
                    model.submitPassword(password, for: network)
                }
                .buttonStyle(.borderedProminent)
                .tint(Brand.accent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .disabled(network.secure && password.isEmpty)

                Button("Choose a Different Network") {
                    password = ""
                    model.rescan()
                }
                .font(.footnote.weight(.medium))
                .foregroundStyle(Brand.muted)
            }
            .padding(24)
        }
    }

    // MARK: - Shared status screen

    @ViewBuilder
    private func statusScreen(
        @ViewBuilder icon: () -> some View,
        title: String,
        subtitle: String,
        @ViewBuilder footer: () -> some View = { EmptyView() }
    ) -> some View {
        VStack(spacing: 20) {
            Spacer()
            icon()
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Brand.text)
                .multilineTextAlignment(.center)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(Brand.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
            Spacer()
            footer()
        }
        .padding(.bottom, 24)
    }
}
