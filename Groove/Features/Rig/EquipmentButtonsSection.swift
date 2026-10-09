import SwiftUI

/// A learn sheet request — one value so `.sheet(item:)` can never present
/// with half-updated state (see the old LearnTarget note in git history).
struct LearnRequestItem: Identifiable {
    let id = UUID()
    let steps: [LearnStep]
}

/// The buttons of one piece of equipment as one list: each row is a real
/// button on its remote. Tap a learned one to send it, an unlearned one to
/// teach it; long-press for Re-learn / Rename / Forget Code / Remove. New
/// buttons are added by learning them ("Add Button…", "Teach the Remote").
struct EquipmentButtonsSection: View {
    let item: RigEquipmentItem
    let model: EquipmentRemoteModel
    /// The amplifier's input buttons have their own section, driven by its
    /// profile — leave them out of this list.
    var excludeInputActions = false
    /// Buttons standard for this device beyond its template (see
    /// `EquipmentRemoteModel.missingStandardButtons`).
    var extraStandard: [String] = []
    let onLearn: ([LearnStep]) -> Void
    let onAddButton: () -> Void

    @State private var renaming: Row?
    @State private var renameText = ""

    struct Row: Identifiable, Hashable {
        let action: String
        let keys: [String]
        let label: String
        var id: String { action }
        var isPower: Bool { EquipmentRemoteModel.powerKeys.contains(action) }
    }

    /// One consolidated Power row (whichever power keys exist), then every
    /// other button in list order — the order the remote shows them.
    private var rows: [Row] {
        let actions = item.actions ?? []
        var out: [Row] = []
        let powerKeys = actions.filter { EquipmentRemoteModel.powerKeys.contains($0) }
        if !powerKeys.isEmpty {
            out.append(Row(action: powerKeys.contains("power_toggle") ? "power_toggle" : powerKeys[0], keys: powerKeys, label: "Power"))
        }
        for a in actions where a != "select_input" && !EquipmentRemoteModel.powerKeys.contains(a) {
            if excludeInputActions && (a == "next_input" || a == "prev_input" || a.hasPrefix("select_")) { continue }
            out.append(Row(action: a, keys: [a], label: item.label(for: a)))
        }
        return out
    }

    private func learned(_ row: Row) -> Bool {
        row.keys.contains { model.isLearned(targetId: item.id, action: $0) }
    }

    var body: some View {
        Section {
            ForEach(rows) { row in rowView(row) }
            Button(action: onAddButton) {
                Label("Add Button…", systemImage: "plus.circle.fill")
            }
            // Only standard buttons still missing prompt a walkthrough —
            // optional extras are offered under Add Button instead, so a
            // complete remote never looks unfinished.
            let missing = model.missingStandardButtons(for: item, extra: extraStandard)
            if !missing.isEmpty {
                Button {
                    onLearn(missing.map { LearnStep(action: $0, label: model.vocabularyLabel($0)) })
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Label(rows.isEmpty ? "Teach the Remote (\(missing.count))" : "Teach the Missing Buttons (\(missing.count))",
                              systemImage: "list.number")
                        Text(missing.map(model.vocabularyLabel).joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(Brand.muted)
                            .padding(.leading, 36)
                    }
                }
            }
        } header: {
            Text("Buttons")
        } footer: {
            Text("Tap a learned button to send it, an unlearned one to teach it. Touch and hold for more.")
                .foregroundStyle(Brand.muted)
        }
        .alert("Rename Button", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $renameText)
            Button("Save") {
                if let row = renaming {
                    Task { await model.renameButton(targetId: item.id, action: row.action, label: renameText.trimmingCharacters(in: .whitespaces)) }
                }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        } message: {
            Text("Leave empty to restore its default name.")
        }
    }

    private func rowView(_ row: Row) -> some View {
        let isLearned = learned(row)
        // Shipped with the amplifier profile: works without teaching, can't
        // be removed; a local code (re-learn) overrides it.
        let hasBuiltin = row.keys.contains { model.hasBuiltinCode(targetId: item.id, action: $0) }
        let onlyBuiltin = hasBuiltin && row.keys.allSatisfy { k in
            !model.isLearned(targetId: item.id, action: k) || model.isBuiltin(targetId: item.id, action: k)
        }
        return Button {
            if isLearned {
                Task { await model.fire(targetId: item.id, action: row.action) }
            } else {
                onLearn([LearnStep(action: row.action, label: row.label)])
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: model.icon(for: row.action) ?? "circle.dashed")
                    .foregroundStyle(isLearned ? Brand.accent : Brand.muted)
                    .frame(width: 24)
                Text(row.label)
                    .foregroundStyle(isLearned ? Brand.text : Brand.muted)
                Spacer()
                if onlyBuiltin {
                    Text("Built-in").font(.caption.weight(.semibold)).foregroundStyle(Brand.ok)
                } else if isLearned {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Brand.ok)
                } else {
                    Text("Teach").font(.caption.weight(.semibold)).foregroundStyle(Brand.accent)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(model.isPerformingAction)
        .swipeActions(edge: .trailing) {
            if !hasBuiltin {
                Button("Remove", role: .destructive) {
                    Task { await model.removeButton(targetId: item.id, actions: row.keys) }
                }
            }
        }
        .contextMenu {
            Button {
                onLearn([LearnStep(action: row.action, label: row.label)])
            } label: {
                Label(isLearned ? "Re-learn" : "Teach", systemImage: "wand.and.stars")
            }
            if !row.isPower {
                Button {
                    renameText = row.label
                    renaming = row
                } label: {
                    Label("Rename", systemImage: "pencil")
                }
            }
            if isLearned && !onlyBuiltin {
                Button {
                    Task { for k in row.keys { await model.unlearn(targetId: item.id, action: k) } }
                } label: {
                    Label(hasBuiltin ? "Use Built-in Code" : "Forget Code", systemImage: "xmark.circle")
                }
            }
            if !hasBuiltin {
                Button(role: .destructive) {
                    Task { await model.removeButton(targetId: item.id, actions: row.keys) }
                } label: {
                    Label("Remove Button", systemImage: "trash")
                }
            }
        }
    }
}
