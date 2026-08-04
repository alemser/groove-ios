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
    /// 1 when the stylus has crossed its configured replacement-alert threshold, else 0 —
    /// surfaced as the Rig tab badge. Not a general count (there's only one hardware
    /// signal worth surfacing today); kept as an Int so the badge modifier stays simple.
    private(set) var rigAttentionCount = 0

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
        guard let settings, settings.isConfigured else { count = 0; rigAttentionCount = 0; return }
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
        await refreshRigAttention(service)
    }

    private func refreshRigAttention(_ service: CatalogService) async {
        guard let stylus = try? await service.stylusState(), stylus.profile != nil else {
            rigAttentionCount = 0
            return
        }
        let defaults = UserDefaults.standard
        let alertsEnabled = (defaults.object(forKey: "stylusAlertEnabled") as? Bool) ?? true
        guard alertsEnabled else { rigAttentionCount = 0; return }
        let threshold = (defaults.object(forKey: "stylusAlertThresholdLeftPercent") as? Int) ?? 15
        let leftPercent = max(0, 100 - stylus.metrics.wearPercent)
        rigAttentionCount = leftPercent <= Double(threshold) ? 1 : 0
    }
}
