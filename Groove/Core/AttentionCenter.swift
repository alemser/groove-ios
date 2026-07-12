import SwiftUI
import Observation

/// Tracks how many items need the user's attention (pending associations plus
/// enrich jobs with candidates awaiting confirmation), so the Review tab and the
/// app icon can carry a live badge. Polls lightly and refreshes on demand after
/// the user acts.
@MainActor
@Observable
final class AttentionCenter {
    private(set) var count = 0

    private var pollTask: Task<Void, Never>?
    private var settings: AppSettings?

    func start(_ settings: AppSettings) {
        self.settings = settings
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    func refresh() async {
        guard let settings, settings.isConfigured else { count = 0; return }
        let service = CatalogService(settings: settings)
        do {
            async let assoc = service.pendingAssociations()
            async let jobs = service.enrichJobs(status: nil)
            let associations = try await assoc.items.count
            // "complete" jobs are the ones carrying release candidates to confirm.
            let actionableJobs = try await jobs.filter { $0.status == "complete" }.count
            count = associations + actionableJobs
        } catch {
            // Leave the last known count on a transient failure.
        }
    }
}
