import SwiftUI
import Observation

/// State for the Audio Input screen: the capture input mode and, on a
/// variable line out, a live level reading the operator sets the detector's
/// capture gain against.
///
/// Gain changes are debounced: every applied step makes the detector
/// re-learn the silence between tracks, so a run of quick −/+ taps should
/// land as one change. The screen still answers each tap at once — the
/// pending step's level is previewed from the dB it adds.
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
    static let applyDelay: Duration = .milliseconds(400)
    /// Fast enough for the live needle to follow the music.
    static let pollInterval: Duration = .milliseconds(250)

    private var settings: AppSettings?
    private var applyTask: Task<Void, Never>?
    @ObservationIgnored private lazy var poller = Poller(interval: Self.pollInterval) { [weak self] in
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

    /// dB of the displayed step (pending or applied); nil without a dB scale.
    var displayedDB: Double? {
        guard let gain = level?.gain, let db = gain.db, let step = displayedStep else { return nil }
        guard step != gain.step else { return db }
        guard let per = gain.dbPerStep else { return nil }
        return db + Double(step - gain.step) * per
    }

    /// Where the level will sit once the pending step applies — the preview
    /// marker. nil when nothing is pending or it can't be predicted.
    var previewRMS: Double? {
        guard let gain = level?.gain, let pending = pendingStep, let per = gain.dbPerStep,
              let programme = level?.programme, programme.rmsP95 > 0 else { return nil }
        return programme.rmsP95 * pow(10, Double(pending - gain.step) * per / 20)
    }

    /// The detector's suggestion, when it differs from where the operator is.
    var suggestedStep: Int? {
        guard let step = level?.programme.suggestedStep, step != displayedStep else { return nil }
        return step
    }

    /// dB the suggestion adds (negative lowers), relative to the applied gain.
    var suggestedDeltaDB: Double? {
        guard let target = suggestedStep, let gain = level?.gain, let per = gain.dbPerStep else { return nil }
        return Double(target - gain.step) * per
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

    /// Switching mode also swaps the gain server-side (each mode keeps its
    /// own), so a −/+ still waiting in the debounce belongs to the mode being
    /// left and must not land on the gain just restored.
    func setVariable(_ variable: Bool) async {
        guard let settings else { return }
        cancelPendingStep()
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
        schedule(target, after: Self.applyDelay)
    }

    /// Jumps straight to the detector's suggestion — one change, no debounce.
    func applySuggestion() {
        guard let target = suggestedStep else { return }
        schedule(target, after: .zero)
    }

    private func schedule(_ target: Int, after delay: Duration) {
        pendingStep = target
        // Cancel only a debounce still sleeping. An apply already on the wire
        // finishes (cancelling it would abort the request mid-flight); this
        // new target is applied after it.
        if !isApplying { applyTask?.cancel() }
        applyTask = Task { [weak self] in
            if delay > .zero { try? await Task.sleep(for: delay) }
            guard !Task.isCancelled else { return }
            await self?.apply(step: target)
        }
    }

    private func cancelPendingStep() {
        if !isApplying { applyTask?.cancel() }
        pendingStep = nil
    }

    private func apply(step: Int) async {
        guard let settings else { return }
        isApplying = true
        defer { isApplying = false }
        do {
            try await CatalogService(settings: settings).rigSetCaptureGain(step: step)
            // The detector rescales its meter on the next capture frame
            // (~46 ms); reading sooner shows the old level for one poll.
            try? await Task.sleep(for: .milliseconds(120))
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
