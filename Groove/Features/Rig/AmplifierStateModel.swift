import SwiftUI
import Observation

/// Follows the amplifier's own reading of its state (`/rig/observe/amplifier`)
/// while the remote is on screen, and raises an `AmplifierHUD` for each
/// change it reports.
@MainActor
@Observable
final class AmplifierStateModel {
    /// nil until the first answer, and after a failed fetch: an older
    /// groove-rig without the endpoint, or the catalog unreachable.
    private(set) var observation: RigAmplifierObservation?
    private(set) var hud: AmplifierHUD?

    /// Chosen: a change the amp made shows up within half a second, about
    /// as long as the amp's own LCD takes to redraw; one small LAN request
    /// per tick, and only while the remote is open.
    static let pollInterval: Duration = .milliseconds(500)
    /// Chosen: long enough to read a value, short enough that a burst of
    /// volume presses reads as one notice that keeps updating.
    static let hudDuration: Duration = .seconds(2)

    /// The amp's power as it reads it itself; nil when there's no provider
    /// reading to go on (fall back to the rig's inference).
    var power: RigAmplifierPower? { observation?.state?.power }

    private var settings: AppSettings?
    private var inputLabels: [String: String] = [:]
    private var hideTask: Task<Void, Never>?
    @ObservationIgnored private lazy var poller = Poller(interval: Self.pollInterval) { [weak self] in
        await self?.refresh()
    }

    func start(_ settings: AppSettings) {
        self.settings = settings
        poller.start()
    }

    func stop() {
        poller.stop()
        hideTask?.cancel()
        hud = nil
    }

    /// Input ids → the labels this profile gives them, for the Input notice.
    func setInputs(_ inputs: [RigInputStatus]) {
        inputLabels = Dictionary(inputs.map { ($0.id, $0.label) }, uniquingKeysWith: { first, _ in first })
    }

    func refresh() async {
        guard let settings, settings.isConfigured else { return }
        let next = try? await CatalogService(settings: settings).rigObserveAmplifier()
        // Only a change between two live readings is news: the first
        // reading, or the first after the provider reconnects, is just the
        // current state.
        if let old = observation?.state, let new = next?.state,
           let change = AmplifierHUD.change(from: old, to: new, inputLabel: { self.inputLabels[$0] ?? $0 }) {
            show(change)
        }
        observation = next
    }

    private func show(_ change: AmplifierHUD) {
        hud = change
        AccessibilityNotification.Announcement("\(change.title) \(change.value)").post()
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: Self.hudDuration)
            guard !Task.isCancelled else { return }
            self?.hud = nil
        }
    }
}
