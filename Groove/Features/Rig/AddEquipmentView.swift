import SwiftUI

/// Registers a new IR-controlled device. Its kind (a groove-rig equipment
/// template) sets type/format and which buttons get suggested — IR can't
/// tell the app what a remote has. Buttons themselves are added afterward
/// by learning them, from the device's screen ("Teach the Remote") —
/// unless a built-in model is picked: groove-rig ships that model's IR
/// codes, so its buttons are registered and work straight away.
struct AddEquipmentView: View {
    let model: EquipmentRemoteModel

    @Environment(\.dismiss) private var dismiss
    @State private var label = ""
    @State private var templateId = ""
    /// "" = no built-in model.
    @State private var modelId = ""
    @State private var isSaving = false

    /// The amplifier template describes the amplifier itself, not new gear.
    private var choices: [RigEquipmentTemplate] {
        model.templates.filter { $0.id != "amplifier" }
    }

    private var selected: RigEquipmentTemplate? {
        choices.first { $0.id == templateId }
    }

    /// Built-in models of the selected kind.
    private var modelChoices: [RigEquipmentModel] {
        model.builtInModels(ofKind: templateId)
    }

    private var selectedModel: RigEquipmentModel? {
        modelChoices.first { $0.id == modelId }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Kind", selection: $templateId) {
                        ForEach(choices) { Text($0.label).tag($0.id) }
                    }
                    // Only when this kind has any — most don't yet.
                    if !modelChoices.isEmpty {
                        Picker("Model", selection: $modelId) {
                            Text("Other / not listed").tag("")
                            ForEach(modelChoices) { Text($0.label).tag($0.id) }
                        }
                    }
                    TextField(namePlaceholder, text: $label)
                        .autocorrectionDisabled()
                } header: {
                    Text("Equipment")
                } footer: {
                    if let m = selectedModel {
                        Text("Oceano already knows the \(m.label)'s remote: \(buttonList(m)) work right away, no remote needed. You can teach any other buttons afterwards.")
                            .foregroundStyle(Brand.muted)
                    } else if let t = selected {
                        Text(t.hasRemote
                             ? "Next, teach its remote: Oceano suggests the \(t.actions.count + t.optionalActions.count) buttons \(t.label.lowercased()) remotes usually have, and you press each one."
                             : "Registered for input mapping only — \(t.label.lowercased())s usually have no remote.")
                            .foregroundStyle(Brand.muted)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .grooveScreenBackground()
            .navigationTitle("Add Equipment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { Task { await save() } }
                        .disabled(isSaving || (label.trimmingCharacters(in: .whitespaces).isEmpty && selected == nil))
                }
            }
            .onAppear {
                if templateId.isEmpty { templateId = choices.first?.id ?? "" }
            }
            // A model belongs to one kind — switching kind drops it.
            .onChange(of: templateId) { _, _ in
                if selectedModel == nil { modelId = "" }
            }
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        let name = label.trimmingCharacters(in: .whitespaces)
        let req = RigEquipmentSaveRequest(
            id: nil,
            label: name.isEmpty ? (selectedModel?.label ?? selected?.label) : name,
            backend: nil, // groove-rig defaults to the amplifier's IR bridge
            actions: [], // learned afterwards — or, with a model, its shipped ones
            role: nil,
            physicalFormat: nil,
            inputIds: nil,
            hasRemote: nil,
            templateId: selected?.id,
            modelId: selectedModel?.id
        )
        if await model.addEquipment(req) {
            dismiss()
        }
    }

    private var namePlaceholder: String {
        if let m = selectedModel { return "Name (default: \(m.label))" }
        return selected.map { "Name (e.g. My \($0.label))" } ?? "Name"
    }

    /// "Play, Stop and Record" from the model's shipped buttons.
    private func buttonList(_ m: RigEquipmentModel) -> String {
        let names = m.actions.map { action in
            model.vocabulary.first { $0.id == action }?.label ?? action.replacingOccurrences(of: "_", with: " ").capitalized
        }
        guard let last = names.last else { return "its buttons" }
        return names.count == 1 ? last : names.dropLast().joined(separator: ", ") + " and " + last
    }
}
