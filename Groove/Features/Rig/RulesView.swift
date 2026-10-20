import SwiftUI

/// Automations groove-rig runs on its own (its `/rules`). One kind today:
/// when AirPlay or Bluetooth starts, power the amplifier on if it reads off
/// and switch it to the input the streamer is wired to. Every change is
/// saved as it's made, like the Streaming screen's device choice.
struct RulesView: View {
    @Environment(AppSettings.self) private var settings

    @State private var rules: [RigRule] = []
    @State private var inputs: [RigInputStatus] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var actionError: String?
    @State private var isSaving = false
    @State private var newInputId = ""

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
                if !rules.contains(where: { $0.when == .streamingStarted && $0.then == .selectInput }) {
                    addSection
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
                    ForEach(inputChoices(including: rule.inputId)) { input in
                        Text(input.label).tag(input.id)
                    }
                }
            }
            Button("Delete Rule", role: .destructive) {
                Task { await delete(rule) }
            }
        } header: {
            Text(triggerTitle(rule.when))
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                if rule.then == .selectInput {
                    Text("Turns the amplifier on first when it reads off. If the rig can't tell whether it's on, it only switches the input.")
                        .foregroundStyle(Brand.muted)
                }
                if !rule.available, let reason = rule.unavailableReason {
                    Text("Can't run yet: \(reason)")
                        .foregroundStyle(Brand.warn)
                }
                if let run = rule.lastRun {
                    Text(lastRunText(run))
                        .foregroundStyle(run.error == nil ? Brand.muted : Brand.err)
                }
            }
        }
    }

    private var addSection: some View {
        Section {
            Picker("Switch amplifier to", selection: $newInputId) {
                ForEach(inputChoices(including: nil)) { input in
                    Text(input.label).tag(input.id)
                }
            }
            Button {
                Task { await create() }
            } label: {
                Label("Add Rule", systemImage: "plus")
            }
            .disabled(newInputId.isEmpty)
        } header: {
            Text(triggerTitle(.streamingStarted))
        } footer: {
            Text("Pick the amplifier input the streamer is wired to. Works when the amplifier is controlled by the rig's remote.")
                .foregroundStyle(Brand.muted)
        }
    }

    private func triggerTitle(_ trigger: RigRuleTrigger) -> String {
        trigger == .streamingStarted ? "When AirPlay or Bluetooth starts" : trigger.rawValue
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

    private func lastRunText(_ run: RigRuleRun) -> String {
        let source = run.source == "bluetooth" ? "Bluetooth" : "AirPlay"
        var text = "Last ran on \(source) at \(Self.formatTime(run.at))"
        if let error = run.error {
            text += " — input not switched: \(error)"
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

    private func load() async {
        guard settings.isConfigured else { return }
        isLoading = true
        errorMessage = nil
        let service = CatalogService(settings: settings)
        // Inputs only fill the pickers: their fetch failing keeps the
        // previous list rather than failing the screen.
        async let status = try? service.rigStatus()
        do {
            rules = try await service.rigRules()
        } catch {
            errorMessage = error.localizedForDisplay
        }
        inputs = await status?.amplifier?.inputs ?? inputs
        if newInputId.isEmpty {
            newInputId = inputs.first(where: \.visible)?.id ?? ""
        }
        isLoading = false
    }

    private func save(_ work: (CatalogService) async throws -> Void) async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await work(CatalogService(settings: settings))
            actionError = nil
            rules = try await CatalogService(settings: settings).rigRules()
        } catch {
            actionError = error.localizedForDisplay
        }
    }

    private func patch(_ rule: RigRule, _ req: RigRulePatchRequest) async {
        await save { try await $0.rigPatchRule(id: rule.id, req) }
    }

    private func create() async {
        let req = RigRuleCreateRequest(when: .streamingStarted, then: .selectInput, inputId: newInputId)
        await save { try await $0.rigCreateRule(req) }
    }

    private func delete(_ rule: RigRule) async {
        await save { try await $0.rigDeleteRule(id: rule.id) }
    }
}
