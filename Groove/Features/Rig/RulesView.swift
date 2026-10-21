import SwiftUI

/// Automations groove-rig runs on its own (its `/rules`), shown as settings:
/// one block per kind of rule, named with an on/off toggle, its options
/// under it. Turning one on for the first time creates the rule; off
/// disables it. The rig says which kinds it offers on this setup (Auto
/// standby only for an amplifier without its own); every change is saved as
/// it's made, like the Streaming screen's device choice.
struct RulesView: View {
    @Environment(AppSettings.self) private var settings

    @State private var rules: [RigRule] = []
    @State private var kinds: [RigRuleKind] = []
    @State private var inputs: [RigInputStatus] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var actionError: String?
    @State private var isSaving = false
    /// Options picked for a rule not created yet, used when it's turned on.
    @State private var newInputId = ""
    @State private var newAfterMins: Int?

    /// One block: a kind the rig offers, or an existing rule whose kind it no
    /// longer offers (shown so it can still be turned off).
    private struct Slot: Identifiable {
        var when: RigRuleTrigger
        var then: RigRuleAction
        var afterMins: RigAfterMinsRange?
        var rule: RigRule?
        var id: String { "\(when.rawValue)→\(then.rawValue)" }
    }

    private var slots: [Slot] {
        let offered = kinds.map { kind in
            Slot(when: kind.when, then: kind.then, afterMins: kind.afterMins,
                 rule: rules.first { $0.when == kind.when && $0.then == kind.then })
        }
        let orphaned = rules
            .filter { rule in !kinds.contains { $0.when == rule.when && $0.then == rule.then } }
            .map { Slot(when: $0.when, then: $0.then, afterMins: nil, rule: $0) }
        return offered + orphaned
    }

    var body: some View {
        Form {
            if isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            } else if let errorMessage {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Couldn't load the rules.")
                        .foregroundStyle(Brand.text)
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(Brand.muted)
                }
            } else {
                ForEach(slots) { slot in
                    section(slot)
                }
                if let actionError {
                    Section {
                        Text(actionError)
                            .font(.footnote)
                            .foregroundStyle(Brand.err)
                    }
                }
            }
        }
        .disabled(isSaving)
        .scrollContentBackground(.hidden)
        .grooveScreenBackground()
        .navigationTitle("Rules")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: - Blocks

    @ViewBuilder
    private func section(_ slot: Slot) -> some View {
        Section {
            Toggle(isOn: Binding(
                get: { slot.rule?.enabled ?? false },
                set: { on in Task { await setEnabled(slot, on) } }
            )) {
                Text(title(slot))
                    .fontWeight(.semibold)
            }
            if slot.then == .selectInput {
                Picker("Set amplifier input to", selection: Binding(
                    get: { slot.rule?.inputId ?? newInputId },
                    set: { id in
                        if let rule = slot.rule {
                            Task { await patch(rule, RigRulePatchRequest(inputId: id)) }
                        } else {
                            newInputId = id
                        }
                    }
                )) {
                    ForEach(inputChoices(including: slot.rule?.inputId)) { input in
                        Text(input.label).tag(input.id)
                    }
                }
            }
            if let range = slot.afterMins {
                let value = slot.rule?.afterMins ?? newAfterMins ?? range.default
                Stepper(
                    "After \(value) min",
                    value: Binding(
                        get: { value },
                        set: { mins in
                            if let rule = slot.rule {
                                Task { await patch(rule, RigRulePatchRequest(afterMins: mins)) }
                            } else {
                                newAfterMins = mins
                            }
                        }
                    ),
                    in: range.min...range.max,
                    step: Self.afterMinsStep
                )
            }
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text(note(slot.then))
                    .foregroundStyle(Brand.muted)
                if let rule = slot.rule, rule.enabled, !rule.available, let reason = rule.unavailableReason {
                    Text("Can't run: \(reason)")
                        .foregroundStyle(Brand.warn)
                }
                if let rule = slot.rule, let run = rule.lastRun {
                    Text(lastRunText(rule, run))
                        .foregroundStyle(run.error == nil ? Brand.muted : Brand.err)
                }
            }
        }
    }

    /// Chosen: five-minute steps cover the 5–720 min range in a handful of
    /// taps per common value without offering false precision.
    private static let afterMinsStep = 5

    // MARK: - Copy

    private func title(_ slot: Slot) -> String {
        switch (slot.when, slot.then) {
        case (.streamingStarted, .selectInput): return "Autoplay when streaming starts"
        case (.inactivity, .powerOff): return "Auto standby"
        default: return "\(slot.when.rawValue) → \(slot.then.rawValue)"
        }
    }

    /// One line under a block: what it does beyond its controls.
    private func note(_ action: RigRuleAction) -> String {
        switch action {
        case .selectInput: return "Also powers the amplifier on, if its remote has a power-on button."
        case .powerOff: return "Turns the amplifier off after this long without music."
        default: return ""
        }
    }

    /// The amplifier's visible inputs, plus a rule's current one even when
    /// hidden or gone, so the picker never shows a blank selection.
    private func inputChoices(including id: String?) -> [RigInputStatus] {
        var choices = inputs.filter(\.visible)
        if let id, !id.isEmpty, !choices.contains(where: { $0.id == id }) {
            choices.append(inputs.first { $0.id == id } ?? RigInputStatus(id: id, label: id, visible: false))
        }
        return choices
    }

    /// "Last run 10:27 · input switched". A power step skipped on purpose
    /// (single power button) isn't news — the note says so — so only a
    /// failed action shows its error.
    private func lastRunText(_ rule: RigRule, _ run: RigRuleRun) -> String {
        let outcome: String
        if let error = run.error {
            outcome = "failed: \(error)"
        } else {
            outcome = rule.then == .selectInput ? "input switched" : "power-off sent"
        }
        return "Last run \(Self.formatTime(run.at)) · \(outcome)"
    }

    /// Time only for today, date and time otherwise.
    private static func formatTime(_ iso: String) -> String {
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = parser.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) else { return iso }
        return Calendar.current.isDateInToday(date)
            ? date.formatted(date: .omitted, time: .shortened)
            : date.formatted(date: .abbreviated, time: .shortened)
    }

    // MARK: - Loading and saving

    private func load() async {
        guard settings.isConfigured else { return }
        isLoading = true
        errorMessage = nil
        let service = CatalogService(settings: settings)
        // Inputs only fill the pickers: their fetch failing keeps the
        // previous list rather than failing the screen.
        async let status = try? service.rigStatus()
        do {
            apply(try await service.rigRules())
        } catch {
            errorMessage = error.localizedForDisplay
        }
        inputs = await status?.amplifier?.inputs ?? inputs
        if newInputId.isEmpty {
            newInputId = inputs.first(where: \.visible)?.id ?? ""
        }
        isLoading = false
    }

    private func apply(_ response: RigRuleListResponse) {
        rules = response.items
        kinds = response.kinds
    }

    private func save(_ work: (CatalogService) async throws -> Void) async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await work(CatalogService(settings: settings))
            actionError = nil
            apply(try await CatalogService(settings: settings).rigRules())
        } catch {
            actionError = error.localizedForDisplay
        }
    }

    private func patch(_ rule: RigRule, _ req: RigRulePatchRequest) async {
        await save { try await $0.rigPatchRule(id: rule.id, req) }
    }

    /// On for a rule not created yet creates it with the options picked in
    /// its block; otherwise it enables or disables the rule.
    private func setEnabled(_ slot: Slot, _ on: Bool) async {
        if let rule = slot.rule {
            await patch(rule, RigRulePatchRequest(enabled: on))
            return
        }
        guard on else { return }
        let req = RigRuleCreateRequest(
            when: slot.when,
            then: slot.then,
            inputId: slot.then == .selectInput ? newInputId : nil,
            afterMins: slot.afterMins.map { newAfterMins ?? $0.default }
        )
        await save { try await $0.rigCreateRule(req) }
    }
}
