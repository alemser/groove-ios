import SwiftUI
import Observation

@MainActor
@Observable
final class AllReleasesModel {
    var releases: [LibraryRelease] = []
    var phase: Phase = .loading
    var actionError: String?
    var deletingId: String?

    enum Phase: Equatable { case loading, loaded, error(String) }

    private var settings: AppSettings?
    private var searchTask: Task<Void, Never>?

    func configure(_ settings: AppSettings) {
        if self.settings == nil {
            self.settings = settings
            Task { await load(query: "") }
        }
    }

    func search(_ query: String) {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await load(query: query)
        }
    }

    /// Unfiltered — unlike `ReleasesModel`'s grid, this mirrors the web
    /// studio's "Releases" management page, which keeps zero-track editions
    /// around specifically so they can be edited or removed.
    func load(query: String) async {
        guard let settings else { return }
        if releases.isEmpty { phase = .loading }
        do {
            releases = try await CatalogService(settings: settings).releases(query: query)
            phase = .loaded
        } catch {
            phase = .error((error as? APIError)?.localizedDescription ?? error.localizedDescription)
        }
    }

    func delete(_ release: LibraryRelease) async {
        guard let settings else { return }
        deletingId = release.id
        do {
            try await CatalogService(settings: settings).deleteLibraryRelease(source: release.source, releaseId: release.releaseId)
            releases.removeAll { $0.id == release.id }
        } catch {
            actionError = (error as? APIError)?.localizedDescription ?? error.localizedDescription
        }
        deletingId = nil
    }
}

/// Every release in the library, mine or reference — the iOS counterpart to
/// the web studio's "Releases" page (`catalog-studio-library.html`). Distinct
/// from the Library tab's grid, which hides zero-track editions; this is
/// where those live on to be edited or removed.
struct AllReleasesView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @State private var model = AllReleasesModel()
    @State private var search = ""
    @State private var mineOnly = false
    @State private var editingRelease: LibraryRelease?
    @State private var deletingRelease: LibraryRelease?
    @State private var showAddRelease = false

    private var filteredReleases: [LibraryRelease] {
        mineOnly ? model.releases.filter(\.owned) : model.releases
    }

    var body: some View {
        content
            .navigationTitle("All Releases")
            .navigationBarTitleDisplayMode(.inline)
            .task { model.configure(settings) }
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search artist or album")
            .onChange(of: search) { _, q in model.search(q) }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAddRelease = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("New Release")
                }
            }
            .grooveScreenBackground()
            .sheet(item: $editingRelease) { release in
                EditReleaseView(release: release) { Task { await model.load(query: search) } }
            }
            .sheet(isPresented: $showAddRelease, onDismiss: { Task { await model.load(query: search) } }) {
                AddReleaseView {}
            }
            .confirmationDialog(
                deleteConfirmTitle,
                isPresented: Binding(get: { deletingRelease != nil }, set: { if !$0 { deletingRelease = nil } }),
                titleVisibility: .visible
            ) {
                Button("Remove", role: .destructive) {
                    if let release = deletingRelease {
                        Task { await model.delete(release) }
                    }
                    deletingRelease = nil
                }
                Button("Cancel", role: .cancel) { deletingRelease = nil }
            } message: {
                Text("The release and its tracklist are deleted. This can't be undone.")
            }
    }

    private var deleteConfirmTitle: String {
        guard let release = deletingRelease else { return "Remove this release?" }
        return "Remove \"\(release.artist) — \(release.album)\" from your library?"
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loading:
            LoadingView()
        case let .error(message):
            ErrorStateView(message: message) { Task { await model.load(query: search) } }
        case .loaded:
            if model.releases.isEmpty {
                EmptyStateView(icon: "square.stack", title: "No releases yet", message: "Confirm a release from a track, or add one from scratch.")
            } else {
                List {
                    Section {
                        Picker("Filter", selection: $mineOnly) {
                            Text("All").tag(false)
                            Text("Mine").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                    }
                    ForEach(filteredReleases) { release in
                        AllReleaseRow(release: release, busy: model.deletingId == release.id)
                            .listRowBackground(Brand.surface)
                            // Full swipe fires the first action — Remove, which
                            // only sets `deletingRelease` and still goes through
                            // the confirmation dialog below, never deletes outright.
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    deletingRelease = release
                                } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                                .disabled(!(release.owned && release.deletable))

                                Button {
                                    editingRelease = release
                                } label: {
                                    Label(release.owned ? "Edit" : "Adopt", systemImage: "pencil")
                                }
                                .tint(Brand.accent)
                                .disabled(!(!release.owned || (release.catalogJobId ?? 0) > 0))
                            }
                    }
                    if let err = model.actionError {
                        Text(err).font(.caption).foregroundStyle(Brand.err).listRowBackground(Color.clear)
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .refreshable { await model.load(query: search) }
            }
        }
    }
}

/// Info-only row — Edit/Remove live in `.swipeActions` on this row (the
/// standard iOS pattern), not inline, so the list reads like any other
/// release list instead of every row carrying its own button pair.
private struct AllReleaseRow: View {
    let release: LibraryRelease
    let busy: Bool

    var body: some View {
        HStack(spacing: 12) {
            Artwork(raw: release.artworkUrl, cornerRadius: 8)
                .frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 3) {
                Text(release.album.nonEmpty ?? "(untitled)")
                    .font(.body.weight(.medium)).foregroundStyle(Brand.text).lineLimit(1)
                Text(release.artist.nonEmpty ?? "?")
                    .font(.subheadline).foregroundStyle(Brand.muted).lineLimit(1)
                HStack(spacing: 6) {
                    Badge(text: release.owned ? "Mine" : release.source.capitalized, color: release.owned ? Brand.accent : Brand.teal)
                    MediaFormatBadge(raw: release.releaseFormat)
                    if let year = release.year?.nonEmpty { Text(year).font(.caption2).foregroundStyle(Brand.muted) }
                }
                Text("\(release.tracklistCount) track\(release.tracklistCount == 1 ? "" : "s") · \(release.catalogTracks) in catalog")
                    .font(.caption2)
                    .foregroundStyle(Brand.muted)
            }
            Spacer(minLength: 8)
            if busy {
                ProgressView()
            }
        }
        .padding(.vertical, 4)
    }
}
