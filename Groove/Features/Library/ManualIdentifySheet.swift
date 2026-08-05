import SwiftUI
import Observation

@MainActor
@Observable
final class ManualIdentifyModel {
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

    func submit(epoch: UInt64, hit: IdentifySearchHit) async -> Bool {
        guard let settings else { return false }
        busyId = hit.id
        actionError = nil
        do {
            _ = try await CatalogService(settings: settings).manualIdentify(
                epoch: epoch,
                artist: hit.artist?.nonEmpty ?? "Unknown artist",
                title: hit.title?.nonEmpty ?? "Untitled",
                album: hit.album,
                hit: hit
            )
            busyId = nil
            return true
        } catch {
            actionError = (error as? APIError)?.localizedDescription ?? error.localizedDescription
            busyId = nil
            return false
        }
    }

    func submitManual(epoch: UInt64, artist: String, title: String, album: String?) async -> Bool {
        guard let settings else { return false }
        actionError = nil
        do {
            _ = try await CatalogService(settings: settings).manualIdentify(epoch: epoch, artist: artist, title: title, album: album)
            return true
        } catch {
            actionError = (error as? APIError)?.localizedDescription ?? error.localizedDescription
            return false
        }
    }
}

/// Search-first recovery for a play recognition couldn't identify at all — the "never
/// heard before" case. Falls back to a two-field manual form so nothing is ever a dead
/// end, mirroring the web studio's search + "Create release" pattern.
struct ManualIdentifySheet: View {
    let epoch: UInt64
    var seedArtist: String?
    var seedTitle: String?
    var seedAlbum: String?
    let onResolved: () -> Void

    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @State private var model = ManualIdentifyModel()
    @State private var query: String
    @State private var showManualEntry = false

    init(
        epoch: UInt64,
        seedArtist: String? = nil,
        seedTitle: String? = nil,
        seedAlbum: String? = nil,
        onResolved: @escaping () -> Void
    ) {
        self.epoch = epoch
        self.seedArtist = seedArtist
        self.seedTitle = seedTitle
        self.seedAlbum = seedAlbum
        self.onResolved = onResolved
        _query = State(initialValue: [seedArtist, seedTitle].compactMap { $0?.nonEmpty }.joined(separator: " "))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                resultsArea
                Divider().overlay(Brand.border)
                manualEntryButton
            }
            .navigationTitle("Identify Play")
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
        .sheet(isPresented: $showManualEntry) {
            ManualEntryForm(seedArtist: seedArtist, seedTitle: seedTitle, seedAlbum: seedAlbum) { artist, title, album in
                await submitManual(artist: artist, title: title, album: album)
            }
        }
    }

    @ViewBuilder
    private var resultsArea: some View {
        switch model.phase {
        case .idle:
            EmptyStateView(icon: "magnifyingglass", title: "Search to identify", message: "Look up the record by artist, album, or track title.")
        case .loading:
            LoadingView()
        case let .error(message):
            ErrorStateView(message: message) { model.search(query) }
        case .loaded:
            if model.results.isEmpty {
                EmptyStateView(icon: "questionmark.circle", title: "No matches", message: "Try a different search, or add it manually below.")
            } else {
                List {
                    ForEach(model.results) { hit in
                        Button {
                            Task { await submit(hit: hit) }
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

    private func submit(hit: IdentifySearchHit) async {
        let ok = await model.submit(epoch: epoch, hit: hit)
        if ok {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            onResolved()
            dismiss()
        }
    }

    private func submitManual(artist: String, title: String, album: String?) async -> String? {
        let ok = await model.submitManual(epoch: epoch, artist: artist, title: title, album: album)
        if ok {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            onResolved()
            dismiss()
            return nil
        }
        return model.actionError ?? "Could not identify this play."
    }
}

struct IdentifyHitRow: View {
    let hit: IdentifySearchHit
    let busy: Bool

    var body: some View {
        HStack(spacing: 12) {
            Artwork(raw: hit.artworkUrl, cornerRadius: 8)
                .frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 3) {
                Text(hit.title?.nonEmpty ?? "Untitled")
                    .font(.body.weight(.medium)).foregroundStyle(Brand.text).lineLimit(1)
                Text(hit.artist?.nonEmpty ?? "Unknown artist")
                    .font(.subheadline).foregroundStyle(Brand.muted).lineLimit(1)
                HStack(spacing: 6) {
                    Badge(text: hit.source, color: Brand.teal)
                    MediaFormatBadge(raw: hit.releaseFormat)
                    if let album = hit.album?.nonEmpty { Text(album).font(.caption2).foregroundStyle(Brand.muted).lineLimit(1) }
                    if let year = hit.releaseDate?.prefix(4), !year.isEmpty { Text(String(year)).font(.caption2).foregroundStyle(Brand.muted) }
                }
            }
            Spacer(minLength: 0)
            if busy {
                ProgressView().tint(Brand.muted)
            } else {
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Brand.muted)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(hit.title?.nonEmpty ?? "Untitled"), \(hit.artist?.nonEmpty ?? "Unknown artist")")
    }
}

struct ManualEntryForm: View {
    var seedArtist: String?
    var seedTitle: String?
    var seedAlbum: String?
    let onSave: (String, String, String?) async -> String?

    @Environment(\.dismiss) private var dismiss
    @State private var artist = ""
    @State private var title = ""
    @State private var album = ""
    @State private var saving = false
    @State private var error: String?

    private var canSave: Bool {
        !artist.trimmingCharacters(in: .whitespaces).isEmpty && !title.trimmingCharacters(in: .whitespaces).isEmpty && !saving
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Artist", text: $artist)
                    TextField("Title", text: $title)
                    TextField("Album (optional)", text: $album)
                } footer: {
                    if let error {
                        Text(error).foregroundStyle(Brand.err)
                    } else {
                        Text("You can pick the exact release and tracklist afterward from Library's Needs Review section.")
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
                                title.trimmingCharacters(in: .whitespaces),
                                album.trimmingCharacters(in: .whitespaces).nonEmpty
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
        .onAppear {
            if artist.isEmpty { artist = seedArtist ?? "" }
            if title.isEmpty { title = seedTitle ?? "" }
            if album.isEmpty { album = seedAlbum ?? "" }
        }
    }
}
