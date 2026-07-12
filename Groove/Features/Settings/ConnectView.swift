import SwiftUI

/// First-run screen: point the app at a groove-catalog server.
struct ConnectView: View {
    @Environment(AppSettings.self) private var settings

    @State private var host = ""
    @State private var port = "7073"
    @State private var scheme = "http"
    @State private var probe = ProbeState.idle

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                header
                form
                connectButton
                if case let .failed(message) = probe {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(Brand.err)
                        .multilineTextAlignment(.center)
                }
                Text("Groove connects to your groove-catalog server on your home network — typically at port 7073.")
                    .font(.footnote)
                    .foregroundStyle(Brand.muted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .padding(24)
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity)
        }
        .grooveScreenBackground()
    }

    private var header: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle().fill(Brand.teal.opacity(0.12)).frame(width: 96, height: 96)
                Image(systemName: "opticaldisc.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(Brand.teal)
            }
            Text("Groove")
                .font(.largeTitle.bold())
                .foregroundStyle(Brand.text)
            Text("Your library, in your pocket")
                .font(.subheadline)
                .foregroundStyle(Brand.muted)
        }
        .padding(.top, 40)
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
