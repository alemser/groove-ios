import SwiftUI

/// Automations groove-rig runs on its own (its `/rules`): when AirPlay or
/// Bluetooth starts, power the amplifier on if it reads off (only with a
/// separate power-on code) and switch it to the streamer's input; and, for
/// an amplifier without its own auto standby, send the power-off signal
/// after a stretch without music. The rig says which kinds it offers on
/// this setup; every change is saved as it's made, like the Streaming
/// screen's device choice.
struct RulesView: View {
    @Environment(AppSettings.self) private var settings

    @State private var rules: [RigRule] = []
    @State private var kinds: [RigRuleKind] = []
    @State private var inputs: [RigInputStatus] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var actionError: String?
    @State private var isSaving = false
    @State private var newInputId = ""
    @State private var newAfterMins: Int?

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
                ForEach(rules) { rule in
                    ruleSection(rule)
                }
                ForEach(kinds.filter { kind in !rules.contains { $0.when == kind.when && $0.then == kind.then } }, id: \.self) { kind in
                    addSection(kind)
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

    // MARK: - Sections

    @ViewBuilder
    private func ruleSection(_ rule: RigRule) -> some View {
        Section {
            Toggle("On", isOn: Binding(
                get: { rule.enabled },
                set: { enabled in Task { await patch(rule, RigRulePatchRequest(enabled: enabled)) } }
            ))
            if rule.then == .selectInput {
                Picker("Switch amplifier to", selection: Binding(
                    get: { rule.inputId ?? "" },
                    set: { id in Task { await patch(rule, RigRulePatchRequest(inputId: id)) } }
                )) {
                    inputOptions(including: rule.inputId)
                }
            }
            if rule.when == .inactivity, let range = afterMinsRange(for: rule) {
                afterMinsStepper(value: rule.afterMins ?? range.default, range: range) { mins in
                    Task { await patch(rule, RigRulePatchRequest(afterMins: mins)) }
                }
            }
            Button("Delete Rule", role: .destructive) {
                Task { await delete(rule) }
            }
        } header: {
            Text(triggerTitle(rule.when))
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text(actionNote(rule.then))
                    .foregroundStyle(Brand.muted)
                if !rule.available, let reason = rule.unavailableReason {
                    Text("Can't run yet: \(reason)")
                        .foregroundStyle(Brand.warn)
                }
                if let run = rule.lastRun {
                    Text(lastRunText(rule, run))
                        .foregroundStyle(run.error == nil ? Brand.muted : Brand.err)
                }
            }
        }
    }

    @ViewBuilder
    private func addSection(_ kind: RigRuleKind) -> some View {
        Section {
            if kind.then == .selectInput {
                Picker("Switch amplifier to", selection: $newInputId) {
                    inputOptions(including: nil)
                }
            }
            if let range = kind.afterMins {
                afterMinsStepper(value: newAfterMins ?? range.default, range: range) { newAfterMins = $0 }
            }
            Button {
                Task { await create(kind) }
            } label: {
                Label("Add Rule", systemImage: "plus")
            }
            .disabled(kind.then == .selectInput && newInputId.isEmpty)
        } header: {
            Text(triggerTitle(kind.when))
        } footer: {
            Text(addNote(kind))
                .foregroundStyle(Brand.muted)
        }
    }

    // MARK: - Controls

    @ViewBuilder
    private func inputOptions(including id: String?) -> some View {
        ForEach(inputChoices(including: id)) { input in
            Text(input.label).tag(input.id)
        }
    }

    private func afterMinsStepper(value: Int, range: RigAfterMinsRange, onChange: @escaping (Int) -> Void) -> some View {
        Stepper(
            "After \(value) min",
            value: Binding(get: { value }, set: onChange),
            in: range.min...range.max,
            step: Self.afterMinsStep
        )
    }

    /// Chosen: five-minute steps cover the 5–720 min range in a handful of
    /// taps per common value without offering false precision.
    private static let afterMinsStep = 5

    /// The rig's after_mins bounds for an existing rule's kind. When the kind
    /// is no longer offered (an amplifier with auto standby now), the rule
    /// keeps its value but can't be edited — it can't run there anyway.
    private func afterMinsRange(for rule: RigRule) -> RigAfterMinsRange? {
        kinds.first { $0.when == rule.when && $0.then == rule.then }?.afterMins
    }

    // MARK: - Copy

    private func triggerTitle(_ trigger: RigRuleTrigger) -> String {
        switch trigger {
        case .streamingStarted: return "When AirPlay or Bluetooth starts"
        case .inactivity: return "When nothing has played for a while"
        default: return trigger.rawValue
        }
    }

    private func actionNote(_ action: RigRuleAction) -> String {
        switch action {
        case .selectInput:
            return "Turns the amplifier on first when it reads off and its remote has a separate power-on button. With a single power button it only switches the input — a press could turn a running amplifier off."
        case .powerOff:
            return "Sends the amplifier's power-off once music or streaming has stopped for this long. Only counts after the rig has heard something play, and skips it if you already switched off from the app. If you switch off with the amplifier's own remote, the rig can't tell — a single power button would turn it back on."
        default:
            return action.rawValue
        }
    }

    private func addNote(_ kind: RigRuleKind) -> String {
        switch kind.then {
        case .selectInput:
            return "Pick the amplifier input the streamer is wired to. Works when the amplifier is controlled by the rig's remote."
        case .powerOff:
            return "This amplifier has no standby of its own, so the rig can switch it off after a quiet spell."
        default:
            return ""
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

    private func lastRunText(_ rule: RigRule, _ run: RigRuleRun) -> String {
        var text = "Last ran"
        if let source = run.source {
            text += " on \(source == "bluetooth" ? "Bluetooth" : "AirPlay")"
        }
        text += " at \(Self.formatTime(run.at))"
        if let error = run.error {
            let what = rule.then == .selectInput ? "input not switched" : "not sent"
            text += " — \(what): \(error)"
        } else if let powerError = run.powerError {
            text += " — input switched; amplifier not powered: \(powerError)"
        } else {
            text += " — done"
        }
        return text
    }

    private static func formatTime(_ iso: String) -> String {
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = parser.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) else { return iso }
        return date.formatted(date: .abbreviated, time: .shortened)
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

    private func create(_ kind: RigRuleKind) async {
        let req = RigRuleCreateRequest(
            when: kind.when,
            then: kind.then,
            inputId: kind.then == .selectInput ? newInputId : nil,
            afterMins: kind.afterMins.map { newAfterMins ?? $0.default }
        )
        await save { try await $0.rigCreateRule(req) }
    }

    private func delete(_ rule: RigRule) async {
        await save { try await $0.rigDeleteRule(id: rule.id) }
    }
}
