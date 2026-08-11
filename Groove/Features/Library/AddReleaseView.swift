import SwiftUI
import Observation

@MainActor
@Observable
final class AddReleaseModel {
    var results: [IdentifySearchHit] = []
    var phase: Phase = .idle
    var busyId: String?
    var creating = false
    var actionError: String?

    enum Phase: Equatable { case idle, loading, loaded, error(String) }

    private var settings: AppSettings?

    func configure(_ settings: AppSettings) {
        self.settings = settings
    }

    /// Explicit lookup, fired only when the user taps Search (or submits a
    /// field) — not per keystroke. Mirrors the web studio's "Lookup using
    /// enrichers": separate Artist/Album fields, one deliberate search.
    func search(artist: String, album: String) {
        let artist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        let album = album.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !artist.isEmpty || !album.isEmpty, let settings else { phase = .idle; results = []; return }
        Task {
            phase = .loading
            do {
                results = try await CatalogService(settings: settings).identifySearch(artist: artist, album: album)
                phase = .loaded
            } catch {
                phase = .error((error as? APIError)?.localizedDescription ?? error.localizedDescription)
            }
        }
    }

    /// Creates a release prefilled from a picked search hit's metadata + tracklist.
    func create(from hit: IdentifySearchHit) async -> (jobId: Int64, draft: PendingRelease)? {
        guard let settings else { return nil }
        busyId = hit.id
        actionError = nil
        defer { busyId = nil }
        do {
            let resp = try await CatalogService(settings: settings).createStandaloneUserRelease(from: hit)
            return (resp.job.id, resp.draft)
        } catch {
            actionError = (error as? APIError)?.localizedDescription ?? error.localizedDescription
            return nil
        }
    }

    /// Creates a blank release from just the typed artist/album, skipping the lookup.
    func create(artist: String, album: String) async -> (jobId: Int64, draft: PendingRelease)? {
        guard let settings else { return nil }
        creating = true
        actionError = nil
        defer { creating = false }
        do {
            let resp = try await CatalogService(settings: settings).createStandaloneUserRelease(artist: artist, album: album)
            return (resp.job.id, resp.draft)
        } catch {
            actionError = (error as? APIError)?.localizedDescription ?? error.localizedDescription
            return nil
        }
    }
}

/// The "cadastro" entry point: Artist + Album fields up front, mirroring the
/// web studio's "New release" dialog — Search looks the pair up against
/// enrichers (only on an explicit tap, never per keystroke), or Save creates
/// directly from what's typed. Either path hands off into `EditReleaseView`
/// to fill in format, tracklist, and artwork before publish.
struct AddReleaseView: View {
    let onCreated: () -> Void

    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: Field?
    @State private var model = AddReleaseModel()
    @State private var artist = ""
    @State private var album = ""
    @State private var created: CreatedDraft?

    private enum Field { case artist, album }

    private var hasQuery: Bool {
        !artist.trimmingCharacters(in: .whitespaces).isEmpty || !album.trimmingCharacters(in: .whitespaces).isEmpty
    }
    private var canCreate: Bool {
        !artist.trimmingCharacters(in: .whitespaces).isEmpty && !album.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Artist", text: $artist)
                        .focused($focusedField, equals: .artist)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .album }
                    TextField("Album", text: $album)
                        .focused($focusedField, equals: .album)
                        .submitLabel(.search)
                        .onSubmit { search() }
                    Button {
                        search()
                    } label: {
                        HStack {
                            Spacer()
                            if model.phase == .loading { ProgressView() }
                            Text("Search")
                            Spacer()
                        }
                    }
                    .disabled(!hasQuery || model.phase == .loading)
                } footer: {
                    Text("Search looks up artist and album against your enrichers to prefill format, tracklist, and artwork.")
                        .foregroundStyle(Brand.muted)
                }

                resultsSection

                Section {
                    Button {
                        Task { await createManual() }
                    } label: {
                        HStack {
                            Spacer()
                            if model.creating { ProgressView() }
                            Text("Save Without Searching")
                            Spacer()
                        }
                    }
                    .disabled(!canCreate || model.creating)
                }

                if let err = model.actionError {
                    Section {
                        Text(err).foregroundStyle(Brand.err)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .grooveScreenBackground()
            .navigationTitle("Add Release")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .sheet(item: $created) { item in
                EditReleaseView(jobId: item.jobId, draft: item.draft) {
                    onCreated()
                    dismiss()
                }
            }
        }
        .task { model.configure(settings) }
        .onAppear { focusedField = .artist }
    }

    @ViewBuilder
    private var resultsSection: some View {
        switch model.phase {
        case .idle:
            EmptyView()
        case .loading:
            Section { LoadingView() }.listRowBackground(Color.clear)
        case let .error(message):
            Section { ErrorStateView(message: message) { search() } }
        case .loaded:
            if model.results.isEmpty {
                Section {
                    Text("No matches. You can still save with just artist and album below.")
                        .font(.caption)
                        .foregroundStyle(Brand.muted)
                }
            } else {
                Section("Results") {
                    ForEach(model.results) { hit in
                        Button {
                            Task { await createFromHit(hit) }
                        } label: {
                            IdentifyHitRow(hit: hit, busy: model.busyId == hit.id)
                        }
                        .buttonStyle(.plain)
                        .disabled(model.busyId != nil)
                        .listRowBackground(Brand.surface)
                    }
                }
            }
        }
    }

    private func search() {
        focusedField = nil
        model.search(artist: artist, album: album)
    }

    private func createFromHit(_ hit: IdentifySearchHit) async {
        guard let result = await model.create(from: hit) else { return }
        created = CreatedDraft(jobId: result.jobId, draft: result.draft)
    }

    private func createManual() async {
        guard let result = await model.create(artist: artist, album: album) else { return }
        created = CreatedDraft(jobId: result.jobId, draft: result.draft)
    }
}

private struct CreatedDraft: Identifiable {
    let jobId: Int64
    let draft: PendingRelease
    var id: Int64 { jobId }
}
