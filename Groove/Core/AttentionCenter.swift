import SwiftUI
import Observation

/// Tracks how many items need the user's attention (pending associations plus
/// tracks still awaiting a confirmed release), so the Library tab can carry a
/// live badge that matches what its "Needs Review" section actually shows.
/// Polls lightly and refreshes on demand after the user acts.
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
            // Same sources that drive the Library grid's banner + "Needs Review"
            // section, so the badge can never disagree with what's actually shown
            // there (an enrich job can sit at status "complete" long after its
            // track was confirmed some other way, so job status alone overcounts).
            async let assoc = service.pendingAssociations()
            async let pending = service.pendingReleaseTracks()
            let associations = try await assoc.items.count
            let pendingTracks = try await pending.count
            count = associations + pendingTracks
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
