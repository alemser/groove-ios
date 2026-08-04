import SwiftUI
import Observation

@MainActor
@Observable
final class LearnSessionModel {
    enum State: Equatable {
        case idle, starting, running, success, failed(String)
    }

    var state: State = .idle

    private var settings: AppSettings?
    private var pollTask: Task<Void, Never>?

    func configure(_ settings: AppSettings) {
        self.settings = settings
    }

    func start(targetId: String, action: String) {
        guard let settings else { return }
        pollTask?.cancel()
        state = .starting
        pollTask = Task {
            let service = CatalogService(settings: settings)
            do {
                let summary = try await service.rigStartLearn(targetId: targetId, action: action)
                await self.poll(sessionId: summary.id, service: service)
            } catch {
                self.state = .failed((error as? APIError)?.localizedDescription ?? error.localizedDescription)
            }
        }
    }

    /// The backend's own learn timeout is 30s; poll a little past that so a
    /// slow-to-arrive "failed" status still lands before we give up locally.
    private func poll(sessionId: String, service: CatalogService) async {
        state = .running
        for _ in 0..<70 {
            guard !Task.isCancelled else { return }
            if let summary = try? await service.rigSession(id: sessionId) {
                switch summary.status {
                case "success":
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    state = .success
                    return
                case "failed":
                    state = .failed(summary.message?.nonEmpty ?? "Learning failed.")
                    return
                default:
                    break
                }
            }
            try? await Task.sleep(for: .milliseconds(500))
        }
        state = .failed("Timed out waiting for the remote signal.")
    }

    func cancel() {
        pollTask?.cancel()
        pollTask = nil
        state = .idle
    }
}
