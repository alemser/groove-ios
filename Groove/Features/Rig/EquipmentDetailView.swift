import SwiftUI

/// One IR device: its buttons (send, teach, add by learning), and
/// equipment removal.
struct EquipmentDetailView: View {
    let item: RigEquipmentItem
    let model: EquipmentRemoteModel

    @Environment(\.dismiss) private var dismiss
    @State private var learnRequest: LearnRequestItem?
    @State private var showAddButton = false
    @State private var showDeleteConfirm = false
    @State private var showEditSheet = false

    private var currentItem: RigEquipmentItem {
        model.equipment.first { $0.id == item.id } ?? item
    }

    var body: some View {
        Form {
            Section("Info") {
                if let name = currentItem.devicelink {
                    InfoRow(label: "DeviceLink", value: name, mono: true)
                    if let device = model.deviceLinkDevice(for: currentItem) {
                        InfoRow(label: "Status", value: device.statusLabel)
                    }
                }
                InfoRow(label: "Role", value: currentItem.role.idWords)
                if currentItem.physicalFormat != "unspecified" {
                    InfoRow(label: "Format", value: currentItem.physicalFormat.capitalized)
                }
                if let m = model.builtInModels.first(where: { $0.id == currentItem.modelId }) {
                    InfoRow(label: "Model", value: m.label)
                }
                if currentItem.id != "amplifier" {
                    let wired = currentItem.wiredInputLabels(model.amplifierInputs)
                    InfoRow(label: "Input", value: wired.isEmpty ? "Not connected" : wired.joined(separator: ", "))
                }
            }

            if let state = model.deviceState(targetId: currentItem.id) {
                DeviceStateSection(state: state)
            }

            if currentItem.devicelink != nil {
                EquipmentButtonsSection(item: currentItem, model: model, onLearn: { _ in }, onAddButton: {})
            } else if currentItem.hasRemote, !(model.snapshot?.irBridgePaired ?? true) {
                Section {
                    Text("Its remote buttons appear once an IR bridge is paired, in Rig › IR Bridge.")
                        .foregroundStyle(Brand.muted)
                }
            } else if currentItem.hasRemote {
                EquipmentButtonsSection(
                    item: currentItem, model: model,
                    onLearn: { learnRequest = LearnRequestItem(steps: $0) },
                    onAddButton: { showAddButton = true }
                )
            } else {
                Section {
                    Text("No remote — registered for input mapping only. Turn on “Show on Remote” in Edit to add buttons.")
                        .foregroundStyle(Brand.muted)
                }
            }

            if let error = model.actionError {
                Section {
                    Text(error).foregroundStyle(Brand.err)
                }
            }

            if currentItem.id != "amplifier" {
                Section {
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label(currentItem.devicelink == nil ? "Delete Equipment" : "Remove Device", systemImage: "trash")
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .grooveScreenBackground()
        .navigationTitle(currentItem.label)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { showEditSheet = true }
            }
        }
        .sheet(item: $learnRequest) { req in
            LearnSessionSheet(
                targetId: currentItem.id, equipmentLabel: currentItem.label, steps: req.steps,
                labelFor: { currentItem.label(for: $0) }
            ) {
                Task { await model.load() }
            }
        }
        .sheet(isPresented: $showAddButton) {
            AddButtonSheet(item: currentItem, model: model) { steps in
                // Present the learn sheet once the picker has gone.
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(350))
                    learnRequest = LearnRequestItem(steps: steps)
                }
            }
        }
        .sheet(isPresented: $showEditSheet) {
            EquipmentEditForm(item: currentItem, model: model)
        }
        .confirmationDialog(
            currentItem.devicelink == nil ? "Delete \(currentItem.label)?" : "Remove \(currentItem.label)?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button(currentItem.devicelink == nil ? "Delete" : "Remove", role: .destructive) {
                Task {
                    await model.remove(currentItem)
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if currentItem.devicelink != nil {
                Text("Everything adding it created goes with it. It can be added again from Rig › Found on Your Network.")
            }
        }
    }
}

/// Which of the active amplifier's inputs a piece of equipment is plugged
/// into; more than one can be ticked, as on `/studio`. Not drawn when the
/// amplifier's inputs aren't known.
struct ConnectedToSection: View {
    let inputs: [RigInputStatus]
    @Binding var ticked: Set<String>

    var body: some View {
        if !inputs.isEmpty {
            Section {
                ForEach(inputs) { input in
                    Toggle(input.label, isOn: Binding(
                        get: { ticked.contains(input.id) },
                        set: { on in
                            if on { ticked.insert(input.id) } else { ticked.remove(input.id) }
                        }
                    ))
                }
            } header: {
                Text("Connected To")
            } footer: {
                Text("The amplifier input it's plugged into. Tick more than one if it is.")
                    .foregroundStyle(Brand.muted)
            }
        }
    }
}

/// Editable equipment attributes — label, role, physical format, built-in
/// model, whether it's exposed on the Remote tab, and which amplifier inputs
/// it's plugged into. A DeviceLink device's own parts aren't edited here:
/// only its label and wiring. Buttons are edited on the device's screen.
struct EquipmentEditForm: View {
    let item: RigEquipmentItem
    let model: EquipmentRemoteModel

    @Environment(\.dismiss) private var dismiss
    @State private var ticked: Set<String> = []
    @State private var label = ""
    @State private var role = "physical_media"
    @State private var physicalFormat = "unspecified"
    @State private var hasRemote = false
    /// "" = no built-in model.
    @State private var modelId = ""
    @State private var isSaving = false

    /// The inputs it can be plugged into; none for the amplifier itself.
    private var wiringInputs: [RigInputStatus] {
        item.id == "amplifier" ? [] : model.amplifierInputs
    }

    /// Built-in models of this equipment's kind — plus its current one, so
    /// the picker can always show what's set.
    private var modelChoices: [RigEquipmentModel] {
        var out = model.builtInModels(ofKind: model.template(for: item)?.id)
        if let current = model.builtInModels.first(where: { $0.id == item.modelId }), !out.contains(current) {
            out.append(current)
        }
        return out
    }

    var body: some View {
        NavigationStack {
            Form {
                if item.devicelink != nil {
                    Section {
                        TextField("Label", text: $label)
                    } footer: {
                        Text("The rest comes from the device itself.")
                            .foregroundStyle(Brand.muted)
                    }
                } else {
                    Section {
                        TextField("Label", text: $label)
                        Picker("Role", selection: $role) {
                            Text("Physical Media").tag("physical_media")
                            Text("Streaming").tag("streaming")
                            Text("Other").tag("other")
                        }
                        Picker("Format", selection: $physicalFormat) {
                            Text("Unspecified").tag("unspecified")
                            Text("Vinyl").tag("vinyl")
                            Text("CD").tag("cd")
                            Text("Tape").tag("tape")
                            Text("Mixed").tag("mixed")
                        }
                        Toggle("Show on Remote", isOn: $hasRemote)
                    }

                    if !modelChoices.isEmpty {
                        Section {
                            Picker("Model", selection: $modelId) {
                                Text("Other / not listed").tag("")
                                ForEach(modelChoices) { Text($0.label).tag($0.id) }
                            }
                        } footer: {
                            Text(modelId.isEmpty
                                 ? "Pick its model if listed: Oceano already knows that remote's buttons, so they work without teaching them."
                                 : "Its main buttons are added and work without teaching; the rest are in Add Button. Choosing “Other” keeps them, but they'll need teaching.")
                                .foregroundStyle(Brand.muted)
                        }
                    }
                }

                ConnectedToSection(inputs: wiringInputs, ticked: $ticked)

                if let error = model.actionError {
                    Section { Text(error).foregroundStyle(Brand.err) }
                }
            }
            .scrollContentBackground(.hidden)
            .grooveScreenBackground()
            .navigationTitle("Edit \(item.label)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") { Task { await save() } }
                        .disabled(isSaving || label.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .onAppear {
            label = item.label
            role = item.role
            physicalFormat = item.physicalFormat
            hasRemote = item.hasRemote
            modelId = item.modelId ?? ""
            ticked = Set(item.inputIds ?? [])
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        let inputs = wiringInputs
        // The amplifier's inputs unknown: nil leaves the wiring as it is.
        let inputIds = inputs.isEmpty ? nil : wiringToSend(ticked, inputs)
        let patch = item.devicelink != nil
            ? RigEquipmentPatchRequest(
                label: label.nonEmpty, backend: nil, actions: nil,
                role: nil, physicalFormat: nil, inputIds: inputIds, hasRemote: nil
            )
            : RigEquipmentPatchRequest(
                label: label.nonEmpty, backend: nil, actions: nil,
                role: role, physicalFormat: physicalFormat, inputIds: inputIds, hasRemote: hasRemote,
                // Only on a change — nil leaves the model as it is.
                modelId: modelId == (item.modelId ?? "") ? nil : modelId
            )
        if await model.updateEquipment(id: item.id, patch) {
            dismiss()
        }
    }
}
