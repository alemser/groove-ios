import SwiftUI
import Observation

@MainActor
@Observable
final class PlaysModel {
    var plays: [Play] = []
    var phase: Phase = .loading
    var includeFailed = false {
        didSet { if oldValue != includeFailed { Task { await reload() } } }
    }

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
        if plays.isEmpty { phase = .loading }
        do {
            let result = try await CatalogService(settings: settings).plays(page: 1, includeFailed: includeFailed)
            plays = result.items
            totalPages = result.totalPages
            phase = .loaded
        } catch {
            if plays.isEmpty { phase = .error((error as? APIError)?.localizedDescription ?? error.localizedDescription) }
        }
        isFetching = false
    }

    func loadMoreIfNeeded(current play: Play) async {
        guard let settings, canLoadMore, !isFetching else { return }
        guard play.id == plays.last?.id else { return }
        isFetching = true
        page += 1
        do {
            let result = try await CatalogService(settings: settings).plays(page: page, includeFailed: includeFailed)
            let existing = Set(plays.map(\.id))
            plays.append(contentsOf: result.items.filter { !existing.contains($0.id) })
            totalPages = result.totalPages
        } catch {
            page -= 1
        }
        isFetching = false
    }

    func delete(_ play: Play) async {
        guard let settings else { return }
        let snapshot = plays
        plays.removeAll { $0.id == play.id }
        do {
            try await CatalogService(settings: settings).deletePlay(epoch: play.listenerEpoch)
        } catch {
            plays = snapshot
        }
    }
}
