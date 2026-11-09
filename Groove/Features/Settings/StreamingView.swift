import SwiftUI

/// The streaming extras — AirPlay and Bluetooth, third-party open-source
/// receivers the user turns on here — and, once one is on, which ALSA device
/// they both play through, out to the amplifier: one wire, one setting.
/// Only the stable `hw:CARD=NAME,DEV=N` ids groove-detector resolves to are
/// trusted, never a numeric card index across a reboot.
struct StreamingView: View {
    @Environment(AppSettings.self) private var settings
    @State private var model = StreamingModel()

    var body: some View {
        Form {
            if model.isLoading && model.extras.isEmpty {
                Section {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }
            } else if let loadError = model.loadError {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Couldn't reach the streaming source.")
                            .foregroundStyle(Brand.text)
                        Text(loadError)
                            .font(.footnote)
                            .foregroundStyle(Brand.muted)
                    }
                }
            } else {
                receiversSection
                if model.anyEnabled {
                    outputSection
                }
            }
        }
        .scrollContentBackground(.hidden)
        .grooveScreenBackground()
        .navigationTitle("Streaming")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            model.configure(settings)
            await model.load()
        }
        .refreshable { await model.load() }
    }

    private var receiversSection: some View {
        Section {
            if !model.available {
                Text("Streaming can't be switched on this Oceano.")
                    .foregroundStyle(Brand.muted)
            }
            ForEach(model.extras) { extra in
                extraRow(extra)
            }
        } header: {
            Text("Receivers")
        } footer: {
            Text("AirPlay comes from shairport-sync, Bluetooth from BlueZ and bluez-alsa: third-party open-source projects, off until you turn them on. Bluetooth is downloaded the first time you turn it on, so Oceano needs internet and it takes a minute or two.")
                .foregroundStyle(Brand.muted)
        }
    }

    private func extraRow(_ extra: StreamingExtra) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: Binding(
                get: { extra.pending ?? extra.enabled },
                set: { on in Task { await model.set(extra.name, enabled: on) } }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(extra.name.title).foregroundStyle(Brand.text)
                    if let progress = progressText(extra) {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.mini)
                            Text(progress).font(.caption).foregroundStyle(Brand.muted)
                        }
                    }
                }
            }
            .disabled(!model.available || model.isChanging)
            if let error = model.changeErrors[extra.name] ?? extra.error {
                Text(error).font(.caption).foregroundStyle(Brand.err)
            }
        }
    }

    private func progressText(_ extra: StreamingExtra) -> String? {
        switch extra.pending {
        case true?: extra.installed ? "Turning on…" : "Installing…"
        case false?: "Turning off…"
        case nil: nil
        }
    }

    private var outputSection: some View {
        Section {
            if model.outputs.isEmpty {
                Text("No playback-capable audio device found. Plug in a DAC and reopen this screen.")
                    .foregroundStyle(Brand.muted)
            } else {
                ForEach(model.outputs) { output in
                    outputRow(output)
                }
            }
            if let outputError = model.outputError {
                Text(outputError).font(.caption).foregroundStyle(Brand.err)
            }
        } header: {
            Text("Output")
        } footer: {
            Text("Which device AirPlay and Bluetooth both play through, out to the amplifier. Pick the one you can hear when you play something — if none of these are audible yet, none is wired to an amp input.")
                .foregroundStyle(Brand.muted)
        }
    }

    private func outputRow(_ output: RigAudioOutput) -> some View {
        let isSelected = output.id == model.selectedOutput
        return Button {
            Task { await model.select(output) }
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
                if model.selectingID == output.id {
                    ProgressView()
                } else if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Brand.teal)
                }
            }
        }
        .disabled(model.selectingID != nil)
    }
}

@MainActor
@Observable
final class StreamingModel {
    var extras: [StreamingExtra] = []
    var available = false
    var outputs: [RigAudioOutput] = []
    var selectedOutput: String?
    var isLoading = true
    var loadError: String?
    /// A switch change the board refused to start, per extra.
    var changeErrors: [StreamingExtraName: String] = [:]
    var outputError: String?
    var selectingID: String?

    private var settings: AppSettings?

    /// Between reads while a change runs on the board. Chosen: an AirPlay
    /// switch takes a second or two and a first Bluetooth install a minute
    /// or two, so a second shows each step without loading the board.
    private static let pollInterval: Duration = .seconds(1)

    var anyEnabled: Bool { extras.contains { $0.enabled } }
    /// The board runs one change at a time.
    var isChanging: Bool { extras.contains { $0.pending != nil } }

    func configure(_ settings: AppSettings) {
        if self.settings == nil { self.settings = settings }
    }

    func load() async {
        guard let settings, settings.isConfigured else { return }
        isLoading = true
        defer { isLoading = false }
        let service = CatalogService(settings: settings)
        do {
            apply(try await service.streamingExtras())
            loadError = nil
        } catch {
            loadError = error.localizedForDisplay
            return
        }
        await loadOutputs()
        await followChange()
    }

    func set(_ name: StreamingExtraName, enabled: Bool) async {
        guard let settings else { return }
        changeErrors[name] = nil
        do {
            apply(try await CatalogService(settings: settings).setStreamingExtra(name, enabled: enabled))
        } catch {
            changeErrors[name] = error.localizedForDisplay
            return
        }
        await followChange()
    }

    func select(_ output: RigAudioOutput) async {
        guard let settings else { return }
        selectingID = output.id
        defer { selectingID = nil }
        do {
            let response = try await CatalogService(settings: settings).rigSelectAudioOutput(device: output.id)
            outputs = response.outputs
            selectedOutput = response.selected.nonEmpty
            outputError = nil
        } catch {
            outputError = error.localizedForDisplay
        }
    }

    /// Reads the extras until no change is running, then the output device
    /// the change may have chosen.
    private func followChange() async {
        guard let settings, isChanging else { return }
        let service = CatalogService(settings: settings)
        while isChanging {
            do {
                try await Task.sleep(for: Self.pollInterval)
                apply(try await service.streamingExtras())
            } catch is CancellationError {
                return
            } catch {
                loadError = error.localizedForDisplay
                return
            }
        }
        await loadOutputs()
    }

    private func loadOutputs() async {
        guard let settings else { return }
        do {
            let response = try await CatalogService(settings: settings).rigAudioOutputs()
            outputs = response.outputs
            selectedOutput = response.selected.nonEmpty
            outputError = nil
        } catch {
            outputError = error.localizedForDisplay
        }
    }

    private func apply(_ response: StreamingExtrasResponse) {
        available = response.available
        extras = response.extras
    }
}
