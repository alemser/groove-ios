import SwiftUI
import Observation

@MainActor
@Observable
final class ChangeReleaseModel {
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

    /// Applies `hit` as `trackId`'s release, returning an error message on
    /// failure or nil on success.
    func apply(trackId: Int64, hit: IdentifySearchHit) async -> String? {
        guard let settings else { return "Not connected" }
        busyId = hit.id
        actionError = nil
        defer { busyId = nil }
        do {
            let result = try await CatalogService(settings: settings).applyReleaseFromSearch(trackId: trackId, hit: hit)
            if result.applied.contains(trackId) { return nil }
            let message = result.failed?.first(where: { $0.trackId == trackId })?.message ?? "Could not apply this release."
            actionError = message
            return message
        } catch {
            let message = (error as? APIError)?.localizedDescription ?? error.localizedDescription
            actionError = message
            return message
        }
    }
}

/// Re-match a track to a different release edition entirely — e.g. swapping a
/// wrongly-picked digital match for the vinyl pressing actually owned. This is
/// distinct from `EditReleaseView`, which only edits fields of whichever
/// release is already confirmed rather than letting you pick a different one.
struct ChangeReleaseSheet: View {
    let trackId: Int64
    var seedArtist: String?
    var seedTitle: String?
    var seedAlbum: String?
    let onApplied: () -> Void

    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @State private var model = ChangeReleaseModel()
    @State private var query: String

    init(
        trackId: Int64,
        seedArtist: String? = nil,
        seedTitle: String? = nil,
        seedAlbum: String? = nil,
        onApplied: @escaping () -> Void
    ) {
        self.trackId = trackId
        self.seedArtist = seedArtist
        self.seedTitle = seedTitle
        self.seedAlbum = seedAlbum
        self.onApplied = onApplied
        _query = State(initialValue: [seedArtist, seedTitle].compactMap { $0?.nonEmpty }.joined(separator: " "))
    }

    var body: some View {
        NavigationStack {
            resultsArea
                .navigationTitle("Change Release")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                }
                .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Artist, album, or track")
                .onChange(of: query) { _, q in model.search(q) }
                .grooveScreenBackground()
        }
        .task {
            model.configure(settings)
            if !query.isEmpty { model.search(query) }
        }
    }

    @ViewBuilder
    private var resultsArea: some View {
        switch model.phase {
        case .idle:
            EmptyStateView(
                icon: "arrow.triangle.2.circlepath",
                title: "Search for the right edition",
                message: "Look up the exact release you own — e.g. the vinyl pressing instead of a digital match."
            )
        case .loading:
            LoadingView()
        case let .error(message):
            ErrorStateView(message: message) { model.search(query) }
        case .loaded:
            if model.results.isEmpty {
                EmptyStateView(icon: "questionmark.circle", title: "No matches", message: "Try a different search.")
            } else {
                List {
                    ForEach(model.results) { hit in
                        Button {
                            Task { await apply(hit) }
                        } label: {
                            IdentifyHitRow(hit: hit, busy: model.busyId == hit.id)
                        }
                        .buttonStyle(.plain)
                        .disabled(model.busyId != nil)
                        .listRowBackground(Brand.surface)
                    }
                    if let err = model.actionError {
                        Text(err).font(.caption).foregroundStyle(Brand.err).listRowBackground(Color.clear)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
    }

    private func apply(_ hit: IdentifySearchHit) async {
        let error = await model.apply(trackId: trackId, hit: hit)
        if error == nil {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            onApplied()
            dismiss()
        }
    }
}
