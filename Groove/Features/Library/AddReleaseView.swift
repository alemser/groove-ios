import SwiftUI
import Observation

@MainActor
@Observable
final class AddReleaseModel {
    var results: [IdentifySearchHit] = []
    var phase: Phase = .idle
    var busyId: String?
    var actionError: String?

    enum Phase: Equatable { case idle, loading, loaded, error(String) }

    private var settings: AppSettings?
    private var searchTask: Task<Void, Never>?

    func configure(_ settings: AppSettings) {
        self.settings = settings
    }

    func search(_ text: String) {
        searchTask?.cancel()
        let q = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { phase = .idle; results = []; return }
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await runSearch(q)
        }
    }

    private func runSearch(_ q: String) async {
        guard let settings else { return }
        phase = .loading
        do {
            results = try await CatalogService(settings: settings).identifySearch(query: q)
            phase = .loaded
        } catch {
            phase = .error((error as? APIError)?.localizedDescription ?? error.localizedDescription)
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

    /// Creates a blank release from just a typed artist/album.
    func create(artist: String, album: String) async -> (jobId: Int64, draft: PendingRelease)? {
        guard let settings else { return nil }
        actionError = nil
        do {
            let resp = try await CatalogService(settings: settings).createStandaloneUserRelease(artist: artist, album: album)
            return (resp.job.id, resp.draft)
        } catch {
            actionError = (error as? APIError)?.localizedDescription ?? error.localizedDescription
            return nil
        }
    }
}

/// The "cadastro" entry point — search first, manual fallback, mirroring
/// `ManualIdentifySheet`'s established pattern for the symmetric case (that
/// screen already documents itself as mirroring "the web studio's search +
/// 'Create release' pattern" for identifying a play; this reuses the same UX
/// for creating a release directly). A pick or a manual save hands off into
/// `EditReleaseView` to fill in format, tracklist, and artwork before publish.
struct AddReleaseView: View {
    let onCreated: () -> Void

    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @State private var model = AddReleaseModel()
    @State private var query = ""
    @State private var showManualEntry = false
    @State private var created: CreatedDraft?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                List {
                    resultsRows
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .overlay {
                    if query.trimmingCharacters(in: .whitespaces).isEmpty {
                        EmptyStateView(icon: "magnifyingglass", title: "Search to add a release", message: "Look it up by artist or album, or add it manually below.")
                    }
                }
                Divider().overlay(Brand.border)
                manualEntryButton
            }
            .navigationTitle("Add Release")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Artist or album")
            .onChange(of: query) { _, q in model.search(q) }
            .grooveScreenBackground()
            .sheet(item: $created) { item in
                EditReleaseView(jobId: item.jobId, draft: item.draft) {
                    onCreated()
                    dismiss()
                }
            }
        }
        .task { model.configure(settings) }
        .sheet(isPresented: $showManualEntry) {
            AddReleaseManualForm { artist, album in
                await createManual(artist: artist, album: album)
            }
        }
    }

    @ViewBuilder
    private var resultsRows: some View {
        switch model.phase {
        case .idle:
            EmptyView()
        case .loading:
            LoadingView()
        case let .error(message):
            ErrorStateView(message: message) { model.search(query) }
        case .loaded:
            if model.results.isEmpty {
                EmptyStateView(icon: "questionmark.circle", title: "No matches", message: "Try a different search, or add it manually below.")
            } else {
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
        if let err = model.actionError {
            Text(err).font(.caption).foregroundStyle(Brand.err).listRowBackground(Color.clear)
        }
    }

    private var manualEntryButton: some View {
        Button {
            showManualEntry = true
        } label: {
            Label("Can't find it? Add manually", systemImage: "square.and.pencil")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.bordered)
        .tint(Brand.accent)
        .padding()
    }

    private func createFromHit(_ hit: IdentifySearchHit) async {
        guard let result = await model.create(from: hit) else { return }
        created = CreatedDraft(jobId: result.jobId, draft: result.draft)
    }

    private func createManual(artist: String, album: String) async -> String? {
        guard let result = await model.create(artist: artist, album: album) else {
            return model.actionError ?? "Could not create this release."
        }
        created = CreatedDraft(jobId: result.jobId, draft: result.draft)
        return nil
    }
}

private struct CreatedDraft: Identifiable {
    let jobId: Int64
    let draft: PendingRelease
    var id: Int64 { jobId }
}

private struct AddReleaseManualForm: View {
    let onSave: (String, String) async -> String?

    @Environment(\.dismiss) private var dismiss
    @State private var artist = ""
    @State private var album = ""
    @State private var saving = false
    @State private var error: String?

    private var canSave: Bool {
        !artist.trimmingCharacters(in: .whitespaces).isEmpty && !album.trimmingCharacters(in: .whitespaces).isEmpty && !saving
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Artist", text: $artist)
                    TextField("Album", text: $album)
                } footer: {
                    if let error {
                        Text(error).foregroundStyle(Brand.err)
                    } else {
                        Text("You can fill in format, tracklist, and artwork on the next screen.")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .grooveScreenBackground()
            .navigationTitle("Add Manually")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Saving…" : "Save") {
                        Task {
                            saving = true
                            let result = await onSave(
                                artist.trimmingCharacters(in: .whitespaces),
                                album.trimmingCharacters(in: .whitespaces)
                            )
                            saving = false
                            if let result {
                                error = result
                            } else {
                                dismiss()
                            }
                        }
                    }
                    .disabled(!canSave)
                }
            }
        }
    }
}
