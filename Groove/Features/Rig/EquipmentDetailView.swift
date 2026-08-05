import SwiftUI

/// One IR device: its registered commands (tap a learned one to send it, an
/// unlearned one to teach it), and equipment removal.
struct EquipmentDetailView: View {
    let item: RigEquipmentItem
    let model: EquipmentRemoteModel

    @Environment(\.dismiss) private var dismiss
    @State private var learnTarget: LearnTarget?
    @State private var showDeleteConfirm = false
    @State private var showEditSheet = false

    private var currentItem: RigEquipmentItem {
        model.equipment.first { $0.id == item.id } ?? item
    }

    /// Carries the action to teach atomically into `.sheet(item:)` — setting
    /// a separate `@State` string and a `Bool` flag in two steps let the
    /// sheet occasionally present with the *previous* action still in place
    /// (SwiftUI can batch the flag flip ahead of the string update), which
    /// sent an empty `action` to `/rig/sessions/learn` and the server
    /// rejected it. A single identifiable value can't be "half updated".
    private struct LearnTarget: Identifiable {
        var id: String { action }
        let action: String
    }

    var body: some View {
        Form {
            Section("Info") {
                InfoRow(label: "Role", value: currentItem.role.replacingOccurrences(of: "_", with: " ").capitalized)
                if currentItem.physicalFormat != "unspecified" {
                    InfoRow(label: "Format", value: currentItem.physicalFormat.capitalized)
                }
            }

            Section {
                ForEach(currentItem.actions ?? [], id: \.self) { action in
                    actionRow(action)
                }
            } header: {
                Text("Commands")
            } footer: {
                Text("Tap a learned command to send it. Tap an unlearned one to teach it from your remote. Swipe or long-press for more options.")
                    .foregroundStyle(Brand.muted)
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
        .sheet(item: $learnTarget) { target in
            LearnSessionSheet(targetId: currentItem.id, action: target.action) {
                Task { await model.load() }
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

    private func actionRow(_ action: String) -> some View {
        let learned = model.isLearned(targetId: currentItem.id, action: action)
        return Button {
            if learned {
                Task { await model.fire(targetId: currentItem.id, action: action) }
            } else {
                teach(action)
            }
        } label: {
            HStack {
                Text(action.replacingOccurrences(of: "_", with: " ").capitalized)
                    .foregroundStyle(Brand.text)
                Spacer()
                if learned {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Brand.ok)
                } else {
                    Text("Not learned").font(.caption).foregroundStyle(Brand.muted)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(model.isPerformingAction)
        .swipeActions(edge: .trailing) {
            if learned {
                Button("Clear", role: .destructive) {
                    Task { await model.unlearn(targetId: currentItem.id, action: action) }
                }
            }
        }
        .contextMenu {
            Button {
                teach(action)
            } label: {
                Label(learned ? "Re-teach" : "Teach", systemImage: "wand.and.stars")
            }
            if learned {
                Button(role: .destructive) {
                    Task { await model.unlearn(targetId: currentItem.id, action: action) }
                } label: {
                    Label("Clear", systemImage: "xmark.circle")
                }
            }
        }
    }

    private func teach(_ action: String) {
        learnTarget = LearnTarget(action: action)
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
