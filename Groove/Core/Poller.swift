import Foundation

/// The `while !Task.isCancelled { await tick(); try? await Task.sleep(...) }`
/// shape shared by every screen that polls groove-catalog for live state
/// (now playing, catalog session, the attention badge) — previously
/// hand-rolled at each call site with its own `Task<Void, Never>?` and
/// start/stop idempotence guard. What each screen does on a tick — surface
/// an error, silently keep the last known value, reset to empty — genuinely
/// differs per screen and stays in the caller's `tick` closure; only the
/// loop/task lifecycle mechanics are centralized here.
@MainActor
final class Poller {
    private var task: Task<Void, Never>?
    private let interval: Duration
    private let tick: @MainActor () async -> Void

    init(interval: Duration, tick: @escaping @MainActor () async -> Void) {
        self.interval = interval
        self.tick = tick
    }

    /// No-op if already running — mirrors the idempotence every hand-rolled
    /// caller had to remember to implement itself.
    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.tick()
                try? await Task.sleep(for: self.interval)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    deinit { task?.cancel() }
}
