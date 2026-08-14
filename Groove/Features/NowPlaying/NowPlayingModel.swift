import SwiftUI
import Observation

@MainActor
@Observable
final class NowPlayingModel {
    var status: CatalogStatus?
    var errorMessage: String?
    var hasLoadedOnce = false

    /// Wall-clock instant the current `status.playback.positionMs` was captured,
    /// so the UI can advance the progress bar smoothly between polls.
    private(set) var positionAnchoredAt = Date()

    /// Wall-clock instant `playback.active` was last true. Track transitions
    /// routinely have a real gap — the previous segment closes and the next
    /// isn't identified yet — where `active` genuinely reads false for a few
    /// seconds even though the listener never stopped. Without this, every
    /// transition flashed the full "Nothing playing" empty state.
    private(set) var lastActiveAt: Date?
    private let transitionGraceInterval: TimeInterval = 25

    private var pollTask: Task<Void, Never>?

    /// True when playback just went inactive but was active moments ago —
    /// "probably between tracks," not "nothing has played all session."
    func isLikelyTransitioning(at now: Date = Date()) -> Bool {
        guard status?.playback.active != true, let lastActiveAt else { return false }
        return now.timeIntervalSince(lastActiveAt) <= transitionGraceInterval
    }

    func start(_ settings: AppSettings) {
        guard pollTask == nil else { return }
        let service = CatalogService(settings: settings)
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh(service)
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    func refresh(_ service: CatalogService) async {
        do {
            let next = try await service.status()
            status = next
            positionAnchoredAt = Date()
            if next.playback.active { lastActiveAt = Date() }
            errorMessage = nil
        } catch {
            errorMessage = (error as? APIError)?.localizedDescription ?? error.localizedDescription
        }
        hasLoadedOnce = true
    }

    /// Interpolated playback position in ms at `now`, clamped to the track length.
    func interpolatedPositionMs(at now: Date) -> Int64? {
        guard let pb = status?.playback, pb.active, let base = pb.positionMs else {
            return status?.playback.positionMs
        }
        let elapsed = Int64(now.timeIntervalSince(positionAnchoredAt) * 1000)
        let value = base + max(0, elapsed)
        if let dur = pb.durationMs, dur > 0 { return min(value, dur) }
        return value
    }
}
