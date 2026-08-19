import SwiftUI

/// The amplifier's own command-teaching screen — same target as
/// `EquipmentDetailView` handles for other equipment, but amplifier-specific
/// because input-navigation rows depend on `input_mode`: a cycle-mode amp
/// (e.g. Magnat MR780) teaches a single Next/Previous pair, while a
/// direct-mode amp (e.g. Denon PMA-600NE, whose remote has one button per
/// input instead of a next/prev button) needs one "Select <input>" row per
/// configured input — those aren't known ahead of time the way transport
/// actions are, so they're derived from `ampConfig.inputs` rather than
/// listed in `item.actions` up front (mirrors studio.html's
/// renderAmplifierIRCard).
struct AmplifierCommandsView: View {
    let item: RigEquipmentItem
    let ampConfig: RigAmplifierConfig?
    let model: EquipmentRemoteModel

    @State private var learnTarget: LearnTarget?

    private struct LearnTarget: Identifiable {
        var id: String { action }
        let action: String
    }

    private var currentItem: RigEquipmentItem {
        model.equipment.first { $0.id == item.id } ?? item
    }

    private var directMode: Bool { ampConfig?.inputMode == "direct" }
    private var visibleInputs: [RigInputConfig] { (ampConfig?.inputs ?? []).filter(\.visible) }

    /// Power/volume/etc. — everything except the input-navigation actions,
    /// which get their own section below driven by `ampConfig` instead of
    /// this list (avoids double-rendering a row once a taught `select_<id>`
    /// lands back in `currentItem.actions` via `ensureActionRegistered`).
    private var genericActions: [String] {
        (currentItem.actions ?? []).filter {
            $0 != "next_input" && $0 != "prev_input" && !$0.hasPrefix("select_")
        }
    }

    var body: some View {
        Form {
            Section {
                ForEach(genericActions, id: \.self) { actionRow($0) }
            } header: {
                Text("Commands")
            } footer: {
                Text("Tap a learned command to send it. Tap an unlearned one to teach it from your remote. Swipe or long-press for more options.")
                    .foregroundStyle(Brand.muted)
            }

            Section {
                if directMode {
                    ForEach(visibleInputs) { input in
                        actionRow("select_" + input.id, label: "Select \(input.label)")
                    }
                } else {
                    ForEach(["next_input", "prev_input"].filter { (currentItem.actions ?? []).contains($0) }, id: \.self) { action in
                        actionRow(action)
                    }
                }
            } header: {
                Text("Input")
            } footer: {
                Text(directMode
                     ? "This amplifier selects each input directly — teach the matching remote button per input."
                     : "This amplifier cycles inputs with a single next/previous button.")
                    .foregroundStyle(Brand.muted)
            }

            if let error = model.actionError {
                Section {
                    Text(error).foregroundStyle(Brand.err)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .grooveScreenBackground()
        .navigationTitle(currentItem.label)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $learnTarget) { target in
            LearnSessionSheet(targetId: currentItem.id, action: target.action) {
                Task {
                    await model.ensureActionRegistered(targetId: currentItem.id, action: target.action)
                    await model.load()
                }
            }
        }
    }

    private func actionRow(_ action: String, label: String? = nil) -> some View {
        let learned = model.isLearned(targetId: currentItem.id, action: action)
        let title = label ?? action.replacingOccurrences(of: "_", with: " ").capitalized
        return Button {
            if learned {
                Task { await model.fire(targetId: currentItem.id, action: action) }
            } else {
                learnTarget = LearnTarget(action: action)
            }
        } label: {
            HStack {
                Text(title).foregroundStyle(Brand.text)
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
                learnTarget = LearnTarget(action: action)
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
}
