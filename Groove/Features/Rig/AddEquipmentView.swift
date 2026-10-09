import SwiftUI

/// Registers a new IR-controlled device. Its kind (a groove-rig equipment
/// template) sets type/format and which buttons get suggested — IR can't
/// tell the app what a remote has. Buttons themselves are added afterward
/// by learning them, from the device's screen ("Teach the Remote").
struct AddEquipmentView: View {
    let model: EquipmentRemoteModel

    @Environment(\.dismiss) private var dismiss
    @State private var label = ""
    @State private var templateId = ""
    @State private var isSaving = false

    /// The amplifier template describes the amplifier itself, not new gear.
    private var choices: [RigEquipmentTemplate] {
        model.templates.filter { $0.id != "amplifier" }
    }

    private var selected: RigEquipmentTemplate? {
        choices.first { $0.id == templateId }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Kind", selection: $templateId) {
                        ForEach(choices) { Text($0.label).tag($0.id) }
                    }
                    TextField(selected.map { "Name (e.g. My \($0.label))" } ?? "Name", text: $label)
                        .autocorrectionDisabled()
                } header: {
                    Text("Equipment")
                } footer: {
                    if let t = selected {
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
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        let name = label.trimmingCharacters(in: .whitespaces)
        let req = RigEquipmentSaveRequest(
            id: nil,
            label: name.isEmpty ? selected?.label : name,
            backend: nil, // groove-rig defaults to the amplifier's IR bridge
            actions: [], // buttons are added by learning them
            role: nil,
            physicalFormat: nil,
            inputIds: nil,
            hasRemote: nil,
            templateId: selected?.id
        )
        if await model.addEquipment(req) {
            dismiss()
        }
    }
}
