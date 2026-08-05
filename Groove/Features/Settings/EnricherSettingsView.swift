import SwiftUI
import Observation

@MainActor
@Observable
final class EnricherSettingsModel {
    var chain: [EnricherSlot] = []
    var phase: Phase = .loading
    var actionError: String?

    enum Phase: Equatable { case loading, loaded, error(String) }

    private var settings: AppSettings?

    func configure(_ settings: AppSettings) {
        if self.settings == nil {
            self.settings = settings
            Task { await load() }
        }
    }

    func load() async {
        guard let settings else { return }
        if chain.isEmpty { phase = .loading }
        do {
            chain = try await CatalogService(settings: settings).enrichers().chain
            phase = .loaded
        } catch {
            if chain.isEmpty {
                phase = .error((error as? APIError)?.localizedDescription ?? error.localizedDescription)
            }
        }
    }

    func setEnabled(id: String, enabled: Bool) async {
        guard let settings else { return }
        do {
            try await CatalogService(settings: settings).setEnricherEnabled(id: id, enabled: enabled)
            await load()
        } catch {
            actionError = (error as? APIError)?.localizedDescription ?? error.localizedDescription
            await load()
        }
    }

    func reorder(_ order: [String]) async {
        guard let settings else { return }
        do {
            chain = try await CatalogService(settings: settings).reorderEnrichers(order: order).chain
            actionError = nil
        } catch {
            actionError = (error as? APIError)?.localizedDescription ?? error.localizedDescription
            await load()
        }
    }

    @discardableResult
    func saveCredentials(id: String, apiKey: String?, params: [String: String]?) async -> Bool {
        guard let settings else { return false }
        do {
            chain = try await CatalogService(settings: settings).setEnricherCredentials(id: id, apiKey: apiKey, params: params).chain
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            actionError = nil
            return true
        } catch {
            actionError = (error as? APIError)?.localizedDescription ?? error.localizedDescription
            return false
        }
    }
}

/// Which metadata enrichers (MusicBrainz, Discogs, iTunes) are enabled, in
/// what order, and with what credentials — fills in a confirmed track's
/// metadata. Distinct from Recognition Providers: this runs after a track is
/// already identified.
struct EnricherSettingsView: View {
    @Environment(AppSettings.self) private var settings
    @State private var model = EnricherSettingsModel()
    @State private var credentialsTarget: CredentialsTarget?

    private struct CredentialsTarget: Identifiable { let id: String }

    var body: some View {
        Group {
            switch model.phase {
            case .loading:
                LoadingView(label: "Loading enrichers…")
            case .error(let message):
                ErrorStateView(message: message) { Task { await model.load() } }
            case .loaded:
                content
            }
        }
        .navigationTitle("Metadata Enrichers")
        .navigationBarTitleDisplayMode(.inline)
        .grooveScreenBackground()
        .task { model.configure(settings) }
        .toolbar { EditButton() }
        .sheet(item: $credentialsTarget) { target in
            EnricherCredentialsForm(providerID: target.id, model: model)
        }
    }

    private var content: some View {
        List {
            Section {
                ForEach(model.chain) { slot in
                    row(slot)
                }
                .onMove { indices, newOffset in
                    var ids = model.chain.map(\.id)
                    ids.move(fromOffsets: indices, toOffset: newOffset)
                    Task { await model.reorder(ids) }
                }
            } header: {
                Text("Order")
            } footer: {
                Text("Tried top to bottom to fill in missing metadata. Drag to reorder; tap a provider to edit its credentials. Changes take effect after the catalog service restarts.")
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

    private func row(_ slot: EnricherSlot) -> some View {
        HStack(spacing: 12) {
            Button {
                credentialsTarget = CredentialsTarget(id: slot.id)
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(slot.displayName ?? slot.id.capitalized).foregroundStyle(Brand.text)
                        Text(slot.configured ? "Configured" : "No credentials")
                            .font(.caption)
                            .foregroundStyle(slot.configured ? Brand.ok : Brand.muted)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Brand.muted)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit \(slot.displayName ?? slot.id) credentials")

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
}
