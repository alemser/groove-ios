import SwiftUI
import Observation

/// One button to teach. `action` nil = a custom button named `label` (the
/// server slugs its id). `fixed` rows (the amplifier's input buttons) exist
/// because of the amplifier profile, so their label isn't stored.
struct LearnStep: Hashable, Identifiable {
    var action: String?
    var label: String
    var fixed: Bool = false
    var id: String { (action ?? "custom:") + label }
}

/// Teaches one button, or walks through several ("Teach the Remote").
/// Adding a button *is* learning it: sessions run with `register`, so a
/// button only joins the equipment once its code is captured — cancel, skip
/// or a timeout leave nothing behind.
@MainActor
@Observable
final class LearnSessionModel {
    enum State: Equatable {
        case idle, starting, running, success
        case failed(String)
        /// Captured, but it's the same press as these other buttons.
        case duplicate([String])
        case finished
    }

    var state: State = .idle
    private(set) var steps: [LearnStep] = []
    private(set) var index = 0
    /// How many buttons were actually learned in this sheet.
    private(set) var learnedCount = 0

    private var settings: AppSettings?
    private var targetId = ""
    private var pollTask: Task<Void, Never>?
    private var sessionId: String?

    var current: LearnStep? { steps.indices.contains(index) ? steps[index] : nil }
    var isWalkthrough: Bool { steps.count > 1 }

    func configure(_ settings: AppSettings) {
        self.settings = settings
    }

    func begin(targetId: String, steps: [LearnStep]) {
        self.targetId = targetId
        self.steps = steps
        index = 0
        learnedCount = 0
        startCurrent()
    }

    func retry() { startCurrent() }

    /// Keep a capture flagged as a duplicate (some remotes really share a code).
    func keep() { advance(learned: true) }

    func skip() {
        Task { await cancelSession() }
        advance(learned: false)
    }

    func stop() {
        Task { await cancelSession() }
        pollTask?.cancel()
        pollTask = nil
        state = .finished
    }

    private func advance(learned: Bool) {
        if learned { learnedCount += 1 }
        index += 1
        if current == nil {
            state = .finished
        } else {
            startCurrent()
        }
    }

    private func startCurrent() {
        guard let settings, let step = current else { return }
        pollTask?.cancel()
        state = .starting
        pollTask = Task {
            let service = CatalogService(settings: settings)
            do {
                let summary = try await service.rigStartLearn(
                    targetId: targetId, action: step.action, label: step.fixed ? nil : step.label
                )
                self.sessionId = summary.id
                await self.poll(sessionId: summary.id, service: service)
            } catch {
                self.state = .failed(error.localizedForDisplay)
            }
        }
    }

    /// The backend's own learn timeout is 30s; poll a little past that so a
    /// slow-to-arrive "failed" status still lands before we give up locally.
    private func poll(sessionId: String, service: CatalogService) async {
        state = .running
        for _ in 0..<70 {
            guard !Task.isCancelled, self.sessionId == sessionId else { return }
            if let summary = try? await service.rigSession(id: sessionId) {
                guard self.sessionId == sessionId else { return }
                switch summary.status {
                case "success":
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    self.sessionId = nil
                    if let dups = summary.duplicateOf, !dups.isEmpty {
                        UINotificationFeedbackGenerator().notificationOccurred(.warning)
                        state = .duplicate(dups)
                    } else if isWalkthrough {
                        advance(learned: true)
                    } else {
                        learnedCount += 1
                        state = .success
                    }
                    return
                case "failed":
                    self.sessionId = nil
                    let message = summary.message?.nonEmpty ?? "Learning failed."
                    state = .failed(message == "cancelled" ? "Cancelled." : message)
                    return
                default:
                    break
                }
            }
            try? await Task.sleep(for: .milliseconds(500))
        }
        state = .failed("Nothing was received in time — try holding the remote closer.")
    }

    /// Tells groove-rig to stop listening: otherwise the bridge keeps
    /// waiting for its full timeout and could take the next button's press.
    private func cancelSession() async {
        guard let settings, let id = sessionId else { return }
        sessionId = nil
        try? await CatalogService(settings: settings).rigCancelSession(id: id)
    }

    func cancel() {
        stop()
        state = .idle
    }
}
