import SwiftUI
import Observation

@MainActor
@Observable
final class TracksModel {
    var tracks: [Track] = []
    var phase: Phase = .loading

    enum Phase: Equatable { case loading, loaded, error(String) }

    private var page = 1
    private var totalPages = 1
    private var isFetching = false
    private var settings: AppSettings?

    func configure(_ settings: AppSettings) {
        if self.settings == nil {
            self.settings = settings
            Task { await reload() }
        }
    }

    var canLoadMore: Bool { page < totalPages }

    func reload() async {
        guard let settings else { return }
        page = 1
        isFetching = true
        if tracks.isEmpty { phase = .loading }
        do {
            let result = try await CatalogService(settings: settings).tracks(page: 1)
            tracks = result.items
            totalPages = result.totalPages
            phase = .loaded
        } catch {
            if tracks.isEmpty { phase = .error((error as? APIError)?.localizedDescription ?? error.localizedDescription) }
        }
        isFetching = false
    }

    func loadMoreIfNeeded(current track: Track) async {
        guard let settings, canLoadMore, !isFetching, track.id == tracks.last?.id else { return }
        isFetching = true
        page += 1
        do {
            let result = try await CatalogService(settings: settings).tracks(page: page)
            let existing = Set(tracks.map(\.id))
            tracks.append(contentsOf: result.items.filter { !existing.contains($0.id) })
            totalPages = result.totalPages
        } catch {
            page -= 1
        }
        isFetching = false
    }
}
