import SwiftUI

/// One IR device: its registered commands (tap a learned one to send it, an
/// unlearned one to teach it), and equipment removal.
struct EquipmentDetailView: View {
    let item: RigEquipmentItem
    let model: EquipmentRemoteModel

    @Environment(\.dismiss) private var dismiss
    @State private var showLearnSheet = false
    @State private var pendingAction = ""
    @State private var showDeleteConfirm = false

    private var currentItem: RigEquipmentItem {
        model.otherEquipment.first { $0.id == item.id } ?? item
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

            Section {
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Label("Delete Equipment", systemImage: "trash")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .grooveScreenBackground()
        .navigationTitle(currentItem.label)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showLearnSheet) {
            LearnSessionSheet(targetId: currentItem.id, action: pendingAction) {
                Task { await model.load() }
            }
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
        pendingAction = action
        showLearnSheet = true
    }
}
