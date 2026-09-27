import SwiftUI
import Observation

/// State for the Audio Input screen: the capture input mode and, on a
/// variable line out, a live programme-level reading the operator sets the
/// detector's capture gain against.
///
/// Gain changes are debounced on purpose. Every applied step makes the
/// detector restart its level measurement and re-learn the silence between
/// tracks, so a run of quick −/+ taps should land as one change, not five.
@MainActor
@Observable
final class AudioInputModel {
    var level: CaptureLevel?
    var phase: Phase = .loading
    var actionError: String?
    /// The step the operator is heading to while a debounced apply is pending.
    private(set) var pendingStep: Int?
    private(set) var isApplying = false

    enum Phase: Equatable { case loading, loaded, error(String) }

    /// How long −/+ taps are coalesced before the gain is applied.
    static let applyDelay: Duration = .milliseconds(700)

    private var settings: AppSettings?
    private var applyTask: Task<Void, Never>?
    @ObservationIgnored private lazy var poller = Poller(interval: .seconds(1)) { [weak self] in
        await self?.refresh()
    }

    var isVariable: Bool { level?.inputLevel == .variable }

    /// The step to show: where the operator is heading, else what is applied.
    var displayedStep: Int? { pendingStep ?? level?.gain?.step }

    var canStepDown: Bool { (displayedStep ?? 0) > 0 && level?.gain != nil }

    var canStepUp: Bool {
        guard let gain = level?.gain, let step = displayedStep else { return false }
        return step < gain.maxStep
    }

    func start(_ settings: AppSettings) {
        self.settings = settings
        poller.start()
    }

    func stop() {
        poller.stop()
    }

    func refresh() async {
        guard let settings, settings.isConfigured else { return }
        do {
            level = try await CatalogService(settings: settings).rigCaptureLevel()
            phase = .loaded
        } catch {
            // Keep showing the last reading through a blip; only an empty
            // screen turns into an error.
            if level == nil { phase = .error(error.localizedForDisplay) }
        }
    }

    func setVariable(_ variable: Bool) async {
        guard let settings else { return }
        let mode: CaptureInputLevel = variable ? .variable : .fixed
        let previous = level?.inputLevel
        level?.inputLevel = mode
        do {
            try await CatalogService(settings: settings).rigSetCaptureInputLevel(mode)
            await refresh()
        } catch {
            if let previous { level?.inputLevel = previous }
            actionError = error.localizedForDisplay
        }
    }

    /// Moves the target gain by `delta` steps and (re)schedules the apply.
    func nudge(_ delta: Int) {
        guard let gain = level?.gain, let current = displayedStep else { return }
        let target = min(max(current + delta, 0), gain.maxStep)
        guard target != current else { return }
        pendingStep = target
        // Cancel only a debounce still sleeping. An apply already on the wire
        // finishes (cancelling it would abort the request mid-flight); this
        // new target is applied after it.
        if !isApplying { applyTask?.cancel() }
        applyTask = Task { [weak self] in
            try? await Task.sleep(for: Self.applyDelay)
            guard !Task.isCancelled else { return }
            await self?.apply(step: target)
        }
    }

    private func apply(step: Int) async {
        guard let settings else { return }
        isApplying = true
        defer { isApplying = false }
        do {
            try await CatalogService(settings: settings).rigSetCaptureGain(step: step)
            await refresh()
            UISelectionFeedbackGenerator().selectionChanged()
        } catch is CancellationError {
            // Superseded; the newer target applies on its own.
        } catch {
            actionError = error.localizedForDisplay
        }
        // A newer tap may have re-targeted while this request was in flight.
        if pendingStep == step { pendingStep = nil }
    }
}
