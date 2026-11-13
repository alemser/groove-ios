import SwiftUI

/// Guided Wi-Fi setup. A first setup ends with the phone back on its own
/// Wi-Fi, where `ConnectView`'s discovery finds the board; a change ends with
/// the board on the chosen network.
///
/// `homeHost` is the board's address on the home network, for a change; nil
/// for a first setup.
struct WifiSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: WifiSetupModel
    @State private var password = ""

    init(homeHost: String? = nil) {
        _model = State(initialValue: WifiSetupModel(homeHost: homeHost))
    }

    var body: some View {
        NavigationStack {
            content
                .grooveScreenBackground()
                .navigationTitle(model.isChange ? "Change Wi-Fi Network" : "Set Up Oceano")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
        }
        .task { model.start() }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .joinByHand:
            statusScreen(
                icon: { symbol("wifi", Brand.teal) },
                title: "Join Oceano's setup network",
                subtitle: "In Settings → Wi-Fi, join the network starting with “\(WifiSetup.prefix)”. Its password is printed on Oceano's label. Then come back here.",
                footer: { primaryButton("I've Joined") { model.joinedByHand() } }
            )
        case .loading:
            statusScreen(
                icon: { spinner },
                title: "Asking Oceano which networks it sees…",
                subtitle: "This takes a few seconds."
            )
        case let .pickingNetwork(note):
            networkList(note: note)
        case let .enteringPassword(network, error):
            passwordForm(network, error: error)
        case let .applying(ssid):
            statusScreen(
                icon: { spinner },
                title: "Connecting to “\(ssid)”…",
                subtitle: "This can take up to half a minute."
            )
        case let .joined(ssid):
            statusScreen(
                icon: { symbol("checkmark.circle.fill", Brand.ok) },
                title: "Connected!",
                subtitle: model.isChange
                    ? "Oceano is on “\(ssid)”."
                    : "Oceano joined “\(ssid)”. Switch your phone back to your own Wi-Fi, where Oceano shows up in a moment.",
                footer: { primaryButton("Done") { dismiss() } }
            )
        case let .moved(ssid):
            statusScreen(
                icon: { symbol("wifi", Brand.teal) },
                title: "Oceano moved to “\(ssid)”",
                subtitle: "It stopped answering on this network, so it's most likely on “\(ssid)” now. Switch your phone to it, and Oceano shows up again.",
                footer: { primaryButton("Done") { dismiss() } }
            )
        case let .failed(message):
            statusScreen(
                icon: { symbol("xmark.circle.fill", Brand.err) },
                title: "Couldn't set up Oceano's Wi-Fi",
                subtitle: message,
                footer: { primaryButton("Try Again") { model.retry() } }
            )
        }
    }

    // MARK: - Network list

    private func networkList(note: String?) -> some View {
        ScrollView {
            VStack(spacing: 14) {
                Text(model.boardName.isEmpty ? "Choose a Wi-Fi network" : "Choose a Wi-Fi network for Oceano \(model.boardName)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Brand.muted)
                if let note {
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(Brand.err)
                        .multilineTextAlignment(.center)
                }
                if !model.networks.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(model.networks) { network in
                            Button {
                                password = ""
                                model.select(network)
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
                Button("Search Again") { model.rescan() }
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Brand.muted)
                    .padding(.top, 4)
            }
            .padding(24)
        }
    }

    private func networkRow(_ network: WifiNetwork) -> some View {
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

    private func passwordForm(_ network: WifiNetwork, error: String?) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 8) {
                    Image(systemName: "wifi.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(Brand.teal)
                    Text(network.ssid)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Brand.text)
                    // A first setup sent the person to the label a step earlier.
                    if !model.isChange {
                        Text("The password of this Wi-Fi network, not the one on Oceano's label.")
                            .font(.footnote)
                            .foregroundStyle(Brand.muted)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.top, 24)

                SecretField("Password", text: $password)
                    .padding(16)
                    .foregroundStyle(Brand.text)
                    .grooveCard()

                if let error {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(Brand.err)
                        .multilineTextAlignment(.center)
                }

                primaryButton("Connect") { model.submit(network, psk: password) }
                    .disabled(password.isEmpty)

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

    // MARK: - Shared pieces

    private var spinner: some View {
        ProgressView().controlSize(.large).tint(Brand.accent)
    }

    private func symbol(_ name: String, _ color: Color) -> some View {
        Image(systemName: name)
            .font(.system(size: 56))
            .foregroundStyle(color)
    }

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.borderedProminent)
            .tint(Brand.accent)
            .controlSize(.large)
    }

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
