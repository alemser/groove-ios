import SwiftUI
import Observation

@MainActor
@Observable
final class ReviewModel {
    var associations: [PendingAssociation] = []
    var jobs: [EnrichJob] = []
    var phase: Phase = .loading

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
        let service = CatalogService(settings: settings)
        if associations.isEmpty && jobs.isEmpty { phase = .loading }
        do {
            async let assoc = service.pendingAssociations()
            async let jobList = service.enrichJobs(status: nil)
            associations = try await assoc.items
            jobs = try await jobList
            phase = .loaded
        } catch {
            if associations.isEmpty && jobs.isEmpty {
                phase = .error((error as? APIError)?.localizedDescription ?? error.localizedDescription)
            }
        }
    }

    func acceptSuggestion(_ item: PendingAssociation) async {
        guard let settings, let trackId = item.suggestedTrackId, trackId > 0 else { return }
        associations.removeAll { $0.id == item.id }
        do {
            try await CatalogService(settings: settings).associatePlay(epoch: item.listenerEpoch, trackId: trackId)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            await load()
        }
    }

    func dismiss(_ item: PendingAssociation) async {
        guard let settings else { return }
        associations.removeAll { $0.id == item.id }
        do {
            try await CatalogService(settings: settings).dismissPendingAssociation(epoch: item.listenerEpoch)
        } catch {
            await load()
        }
    }

    var pendingJobCount: Int { jobs.filter { $0.status == "pending" || $0.status == "enriching" }.count }
}
