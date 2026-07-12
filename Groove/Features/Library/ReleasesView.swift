import SwiftUI
import Observation

@MainActor
@Observable
final class ReleasesModel {
    var releases: [LibraryRelease] = []
    var phase: Phase = .loading
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
}

struct ReleasesView: View {
    @Environment(AppSettings.self) private var settings
    @State private var model = ReleasesModel()
    @State private var search = ""

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 16)]

    var body: some View {
        content
            .task { model.configure(settings) }
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Search releases")
            .onChange(of: search) { _, q in model.search(q) }
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
                EmptyStateView(icon: "square.stack", title: search.isEmpty ? "No releases" : "No matches",
                               message: search.isEmpty ? "Confirm a release from the Review tab to build your collection." : nil)
            } else {
                grid
            }
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(model.releases) { release in
                    NavigationLink(value: release) {
                        ReleaseCardView(release: release)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
        .scrollContentBackground(.hidden)
        .refreshable { await model.load(query: search) }
    }
}

struct ReleaseCardView: View {
    let release: LibraryRelease

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Artwork(raw: release.artworkUrl, cornerRadius: 12)
                .aspectRatio(1, contentMode: .fit)
                .overlay(alignment: .topTrailing) {
                    if release.owned {
                        Image(systemName: "person.crop.circle.badge.checkmark")
                            .font(.caption)
                            .padding(6)
                            .background(.ultraThinMaterial, in: Circle())
                            .padding(6)
                    }
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(release.album)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Brand.text)
                    .lineLimit(1)
                Text(release.artist)
                    .font(.caption)
                    .foregroundStyle(Brand.muted)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if let year = release.year?.nonEmpty {
                        Text(year).font(.caption2).foregroundStyle(Brand.muted)
                    }
                    if let media = Format.mediaFormat(release.releaseFormat) {
                        Badge(text: media, color: Brand.gold)
                    }
                }
            }
        }
    }
}
