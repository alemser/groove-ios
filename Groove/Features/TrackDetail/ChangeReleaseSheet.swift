import SwiftUI
import Observation

@MainActor
@Observable
final class ChangeReleaseModel {
    var results: [IdentifySearchHit] = []
    var phase: Phase = .idle
    /// Library search runs independently of the enricher search below: it needs
    /// no enrichers configured and no network beyond the LAN, so it must not be
    /// blocked or hidden by an enricher error — same fix as `ManualIdentifySheet`
    /// (groove-identity#32), applied here so re-matching a confirmed track also
    /// works with enrichers unreachable (offline mode / cloud autônomo down).
    var libraryResults: [LibraryReleaseSearchHit] = []
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
        guard !q.isEmpty else { phase = .idle; results = []; libraryResults = []; return }
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            async let library: () = runLibrarySearch(q)
            async let external: () = runSearch(q)
            _ = await (library, external)
        }
    }

    private func runLibrarySearch(_ q: String) async {
        guard let settings else { return }
        libraryResults = (try? await CatalogService(settings: settings).searchLibraryReleases(query: q)) ?? []
    }

    private func runSearch(_ q: String) async {
        guard let settings else { return }
        phase = .loading
        do {
            results = try await CatalogService(settings: settings).identifySearch(query: q)
            phase = .loaded
        } catch {
            phase = .error(error.localizedForDisplay)
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
            let message = error.localizedForDisplay
            actionError = message
            return message
        }
    }

    /// Same as `apply(trackId:hit:)` but for a hit picked from the library
    /// search — mapped onto the same `apply-release-from-search` wire shape
    /// the web studio uses for its own library-edition results
    /// (`searchHitFromLibrary` in release-matching.js).
    func apply(trackId: Int64, libraryHit: LibraryReleaseSearchHit) async -> String? {
        await apply(trackId: trackId, hit: IdentifySearchHit(
            source: libraryHit.source ?? "",
            artist: libraryHit.artist,
            title: nil,
            album: libraryHit.album,
            isrc: nil,
            recordingId: nil,
            releaseId: libraryHit.releaseId,
            releaseGroupId: nil,
            releaseType: nil,
            releaseFormat: nil,
            trackNumber: nil,
            trackTotal: nil,
            discNumber: nil,
            durationMs: nil,
            releaseDate: libraryHit.year,
            country: nil,
            label: nil,
            artworkUrl: libraryHit.artworkUrl
        ))
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

    /// Library results render regardless of `model.phase` — that phase only
    /// tracks the enricher search, which needs neither enrichers configured
    /// nor cloud reachability, so a library-only match (the common offline-mode
    /// case) must never be hidden behind an enricher error or idle state.
    @ViewBuilder
    private var resultsArea: some View {
        List {
            if !model.libraryResults.isEmpty {
                Section("Your Library") {
                    ForEach(model.libraryResults) { hit in
                        Button {
                            Task { await apply(libraryHit: hit) }
                        } label: {
                            LibraryReleaseHitRow(hit: hit)
                        }
                        .buttonStyle(.plain)
                        .disabled(model.busyId != nil)
                        .listRowBackground(Brand.surface)
                    }
                }
            }
            Section(model.libraryResults.isEmpty ? "" : "Enrichers") {
                enricherRows
            }
            if let err = model.actionError {
                Text(err).font(.caption).foregroundStyle(Brand.err).listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .overlay {
            if model.libraryResults.isEmpty && query.trimmingCharacters(in: .whitespaces).isEmpty {
                EmptyStateView(
                    icon: "arrow.triangle.2.circlepath",
                    title: "Search for the right edition",
                    message: "Look up the exact release you own — e.g. the vinyl pressing instead of a digital match."
                )
            }
        }
    }

    /// Enricher-search rows only — no List wrapper, no idle/empty state (the
    /// parent List and its overlay own those, since library results share the
    /// same screen and must not be hidden behind an enricher-only switch).
    @ViewBuilder
    private var enricherRows: some View {
        switch model.phase {
        case .idle:
            EmptyView()
        case .loading:
            if model.libraryResults.isEmpty {
                LoadingView()
            }
        case let .error(message):
            if model.libraryResults.isEmpty {
                ErrorStateView(message: message) { model.search(query) }
            } else {
                Text("Enrichers: \(message)").font(.caption).foregroundStyle(Brand.muted)
            }
        case .loaded:
            if model.results.isEmpty {
                if model.libraryResults.isEmpty {
                    EmptyStateView(icon: "questionmark.circle", title: "No matches", message: "Try a different search.")
                }
            } else {
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

    private func apply(libraryHit hit: LibraryReleaseSearchHit) async {
        let error = await model.apply(trackId: trackId, libraryHit: hit)
        if error == nil {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            onApplied()
            dismiss()
        }
    }
}
