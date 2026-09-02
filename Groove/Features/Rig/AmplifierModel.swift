import SwiftUI
import Observation

@MainActor
@Observable
final class AmplifierModel {
    var snapshot: RigSnapshot?
    var phase: Phase = .loading
    var actionError: String?
    var isPerformingAction = false

    enum Phase: Equatable { case loading, loaded, error(String) }

    private var settings: AppSettings?
    /// Tail of the serial chain of volume steps — see volume(direction:).
    private var volumeChain: Task<Void, Never>?

    var amplifier: RigAmplifierStatus? { snapshot?.amplifier }
    var amplifierTarget: RigTargetStatus? { snapshot?.targets.first { $0.id == "amplifier" } }
    var visibleInputs: [RigInputStatus] { (amplifier?.inputs ?? []).filter(\.visible) }

    func isLearned(_ action: String) -> Bool {
        amplifierTarget?.actions[action]?.learned ?? false
    }

    func configure(_ settings: AppSettings) {
        if self.settings == nil {
            self.settings = settings
            Task { await load() }
        }
    }

    func load() async {
        guard let settings else { return }
        if snapshot == nil { phase = .loading }
        do {
            snapshot = try await CatalogService(settings: settings).rigStatus()
            phase = .loaded
        } catch {
            if snapshot == nil {
                phase = .error(error.localizedForDisplay)
            }
        }
    }

    private func perform(_ work: () async throws -> Void) async {
        guard !isPerformingAction else { return }
        isPerformingAction = true
        defer { isPerformingAction = false }
        do {
            try await work()
            actionError = nil
        } catch {
            actionError = error.localizedForDisplay
            // The tap was confirmed by a haptic before the request went out.
            // If it then failed, say so the same way — the error text sits at
            // the bottom of a scrolling screen and is easy to miss.
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    func powerOn() async {
        guard let settings else { return }
        await perform {
            let power = try await CatalogService(settings: settings).rigEnsurePowerOn()
            self.snapshot?.amplifier?.power = power
        }
    }

    func powerOff() async {
        guard let settings else { return }
        await perform {
            let power = try await CatalogService(settings: settings).rigEnsurePowerOff()
            self.snapshot?.amplifier?.power = power
        }
    }

    /// Most amplifier remotes have a single physical power button (one
    /// `power_toggle` IR code), not discrete on/off — mirrors the web
    /// remote's single Power button. Picks on vs. off from the currently
    /// displayed state; the server resolves that intent to whatever's
    /// actually learned (`power_toggle` preferred) either way, so this is
    /// just which single button the UI shows, not a behavior change.
    var isPowerOn: Bool {
        let state = amplifier?.power?.state ?? "unknown"
        return state == "on" || state == "warming_up"
    }

    func togglePower() async {
        if isPowerOn {
            await powerOff()
        } else {
            await powerOn()
        }
    }

    /// Volume is the one control people press in bursts, and perform()'s
    /// one-at-a-time guard DROPPED those taps: press five times while a request
    /// is in flight and only the first is sent, with nothing on screen or in the
    /// hand to say the others went nowhere. That reads as a broken button.
    ///
    /// So volume does not go through perform(). Each press is appended to a
    /// serial chain and sent in order — five presses are five steps, which is
    /// what the amplifier's own remote does. The chain matters: sending them
    /// concurrently would let the rig transmit two IR codes at once.
    func volume(direction: String) async {
        guard let settings else { return }
        let previous = volumeChain
        let task = Task { @MainActor [weak self] in
            _ = await previous?.result
            guard let self else { return }
            do {
                self.snapshot = try await CatalogService(settings: settings).rigAction(action: "volume_\(direction)")
                self.actionError = nil
            } catch {
                self.actionError = error.localizedForDisplay
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        }
        volumeChain = task
        await task.value
    }

    func nextInput() async {
        guard let settings else { return }
        await perform {
            self.snapshot = try await CatalogService(settings: settings).rigAction(action: "next_input")
        }
    }

    func prevInput() async {
        guard let settings else { return }
        await perform {
            self.snapshot = try await CatalogService(settings: settings).rigAction(action: "prev_input")
        }
    }

    func selectInput(id: String) async {
        guard let settings else { return }
        await perform {
            self.snapshot = try await CatalogService(settings: settings).rigSelectInput(
                inputId: id,
                currentInputId: self.amplifier?.activeInputId
            )
        }
    }

    func resyncInput(id: String) async {
        guard let settings else { return }
        await perform {
            try await CatalogService(settings: settings).rigResyncActiveInput(inputId: id)
            self.snapshot = try await CatalogService(settings: settings).rigStatus()
        }
    }
}
