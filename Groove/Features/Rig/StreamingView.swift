import SwiftUI

/// Which ALSA device shairport-sync (AirPlay) plays through, out to the
/// amplifier — the app-side counterpart to the web Studio's Streaming tab
/// (groove-rig's `internal/api/static/studio.html`). Same reasoning there
/// applies here: never trust a numeric card index across a reboot, only the
/// stable `hw:CARD=NAME,DEV=N` ids groove-detector already resolves to.
struct StreamingView: View {
    @Environment(AppSettings.self) private var settings

    @State private var response: RigAudioOutputsResponse?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectingID: String?

    var body: some View {
        Form {
            Section {
                if isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                } else if let errorMessage {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Couldn't reach the streaming source.")
                            .foregroundStyle(Brand.text)
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(Brand.muted)
                    }
                } else if let outputs = response?.outputs, !outputs.isEmpty {
                    ForEach(outputs) { output in
                        outputRow(output)
                    }
                } else {
                    Text("No playback-capable audio device found. Plug in a DAC and reopen this screen.")
                        .foregroundStyle(Brand.muted)
                }
            } footer: {
                Text("Which device AirPlay plays through, out to the amplifier. Pick the one you can hear when you play something — if none of these are audible yet, none is wired to an amp input.")
                    .foregroundStyle(Brand.muted)
            }
        }
        .scrollContentBackground(.hidden)
        .grooveScreenBackground()
        .navigationTitle("Streaming")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private func outputRow(_ output: RigAudioOutput) -> some View {
        let isSelected = output.id == response?.selected
        return Button {
            Task { await select(output) }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(output.label)
                        .foregroundStyle(isSelected ? Brand.teal : Brand.text)
                        .fontWeight(isSelected ? .semibold : .regular)
                    Text(output.id)
                        .font(.caption2.monospaced())
                        .foregroundStyle(Brand.muted)
                }
                Spacer()
                if selectingID == output.id {
                    ProgressView()
                } else if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Brand.teal)
                }
            }
        }
        .disabled(selectingID != nil)
    }

    private func load() async {
        guard settings.isConfigured else { return }
        isLoading = true
        errorMessage = nil
        do {
            response = try await CatalogService(settings: settings).rigAudioOutputs()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func select(_ output: RigAudioOutput) async {
        selectingID = output.id
        do {
            response = try await CatalogService(settings: settings).rigSelectAudioOutput(device: output.id)
        } catch {
            errorMessage = error.localizedDescription
        }
        selectingID = nil
    }
}
