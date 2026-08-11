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
                phase = .error((error as? APIError)?.localizedDescription ?? error.localizedDescription)
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
            actionError = (error as? APIError)?.localizedDescription ?? error.localizedDescription
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

    func volume(direction: String) async {
        guard let settings else { return }
        await perform {
            self.snapshot = try await CatalogService(settings: settings).rigAction(action: "volume_\(direction)")
        }
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
