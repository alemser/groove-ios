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
                InfoRow(label: "Role", value: currentItem.role.replacingOccurrences(of: "_", with: " ").capitalized)
                if currentItem.physicalFormat != "unspecified" {
                    InfoRow(label: "Format", value: currentItem.physicalFormat.capitalized)
                }
            }

            if currentItem.hasRemote {
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
                        Label("Delete Equipment", systemImage: "trash")
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
            "Delete \(currentItem.label)?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                Task {
                    await model.deleteEquipment(id: currentItem.id)
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

/// Editable equipment attributes — label, role, physical format, and whether
/// it's exposed on the Remote tab. Backend/actions/input wiring stay
/// create-time-only for now, edited by re-adding the device if they need to
/// change.
struct EquipmentEditForm: View {
    let item: RigEquipmentItem
    let model: EquipmentRemoteModel

    @Environment(\.dismiss) private var dismiss
    @State private var label = ""
    @State private var role = "physical_media"
    @State private var physicalFormat = "unspecified"
    @State private var hasRemote = false
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
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
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        let patch = RigEquipmentPatchRequest(
            label: label.nonEmpty, backend: nil, actions: nil,
            role: role, physicalFormat: physicalFormat, inputIds: nil, hasRemote: hasRemote
        )
        if await model.updateEquipment(id: item.id, patch) {
            dismiss()
        }
    }
}
