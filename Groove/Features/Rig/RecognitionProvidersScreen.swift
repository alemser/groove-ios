import SwiftUI

/// Which audio-recognition providers (ACRCloud, AudD, the local fingerprint
/// index, …) are enabled and in what order — proxied through `groove-catalog`
/// to `groove-identity`'s `/recognition/providers`. Distinct from Rig's
/// "Metadata Enrichers": this is what identifies a spinning record, not what
/// fills in a confirmed track's metadata.
struct RecognitionProvidersScreen: View {
    @Environment(AppSettings.self) private var settings
    @State private var model = RecognitionProvidersModel()
    @State private var credentialsTarget: CredentialsTarget?

    private struct CredentialsTarget: Identifiable {
        let id: String
    }

    var body: some View {
        Group {
            switch model.phase {
            case .loading:
                LoadingView(label: "Loading providers…")
            case .error(let message):
                ErrorStateView(message: message) { Task { await model.load() } }
            case .loaded:
                content
            }
        }
        .navigationTitle("Recognition Providers")
        .navigationBarTitleDisplayMode(.inline)
        .grooveScreenBackground()
        .task { model.configure(settings) }
        .toolbar { EditButton() }
        .sheet(item: $credentialsTarget) { target in
            ProviderCredentialsView(providerID: target.id, model: model)
        }
    }

    private var content: some View {
        List {
            Section {
                ForEach(model.state?.chain ?? []) { slot in
                    row(slot)
                }
                .onMove { indices, newOffset in
                    guard var ids = model.state?.chain.map(\.id) else { return }
                    ids.move(fromOffsets: indices, toOffset: newOffset)
                    Task { await model.reorder(ids) }
                }
            } header: {
                Text("Chain Order")
            } footer: {
                Text("Tried top to bottom until one identifies the track. Drag to reorder; tap the key to add credentials.")
                    .foregroundStyle(Brand.muted)
            }

            if let error = model.actionError {
                Section {
                    Text(error).foregroundStyle(Brand.err)
                }
            }
        }
        .scrollContentBackground(.hidden)
    }

    private func row(_ slot: ProviderSlot) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(slot.displayName?.nonEmpty ?? slot.id.capitalized)
                    .foregroundStyle(Brand.text)
                Text(subtitle(slot))
                    .font(.caption)
                    .foregroundStyle(subtitleColor(slot))
            }
            Spacer()
            if hasCredentialsForm(slot.id) {
                Button {
                    credentialsTarget = CredentialsTarget(id: slot.id)
                } label: {
                    Image(systemName: "key.fill")
                        .foregroundStyle(Brand.muted)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Edit \(slot.displayName ?? slot.id) credentials")
            }
            Toggle(
                "",
                isOn: Binding(
                    get: { slot.enabled },
                    set: { newValue in Task { await model.setEnabled(id: slot.id, enabled: newValue) } }
                )
            )
            .labelsHidden()
            .tint(Brand.accent)
        }
    }

    private func hasCredentialsForm(_ id: String) -> Bool {
        model.state?.builtins[id] != nil
    }

    private func subtitle(_ slot: ProviderSlot) -> String {
        guard hasCredentialsForm(slot.id) else { return "Local — no credentials needed" }
        return slot.configured ? "Configured" : "Needs credentials"
    }

    private func subtitleColor(_ slot: ProviderSlot) -> Color {
        guard hasCredentialsForm(slot.id) else { return Brand.muted }
        return slot.configured ? Brand.ok : Brand.warn
    }
}
