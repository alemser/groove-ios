import SwiftUI

/// The amplifier's own buttons — same list as `EquipmentDetailView` for
/// power/volume/extras, plus a fixed Input section whose rows depend on
/// `input_mode`: a cycle-mode amp (e.g. Magnat MR780) teaches one
/// Next/Previous pair, a direct-mode amp (e.g. Denon PMA-600NE) one
/// "Select <input>" button per input. Those rows exist because of the
/// profile's inputs, so they can be taught or forgotten but not renamed or
/// removed (mirrors studio.html's renderAmplifierIRCard).
struct AmplifierCommandsView: View {
    let item: RigEquipmentItem
    let ampConfig: RigAmplifierConfig?
    let model: EquipmentRemoteModel

    @State private var learnRequest: LearnRequestItem?
    @State private var showAddButton = false

    private var currentItem: RigEquipmentItem {
        model.equipment.first { $0.id == item.id } ?? item
    }

    private var directMode: Bool { ampConfig?.inputMode == "direct" }
    private var visibleInputs: [RigInputConfig] { (ampConfig?.inputs ?? []).filter(\.visible) }

    private var inputSteps: [LearnStep] {
        if directMode {
            return visibleInputs.map { LearnStep(action: "select_" + $0.id, label: "Select \($0.label)", fixed: true) }
        }
        return [
            LearnStep(action: "prev_input", label: "Previous input", fixed: true),
            LearnStep(action: "next_input", label: "Next input", fixed: true),
        ]
    }

    private func learned(_ step: LearnStep) -> Bool {
        model.isLearned(targetId: currentItem.id, action: step.action ?? "")
    }

    var body: some View {
        Form {
            EquipmentButtonsSection(
                item: currentItem, model: model, excludeInputActions: true,
                onLearn: { learnRequest = LearnRequestItem(steps: $0) },
                onAddButton: { showAddButton = true }
            )

            Section {
                ForEach(inputSteps) { inputRow($0) }
                let unlearned = inputSteps.filter { !learned($0) }
                if !unlearned.isEmpty {
                    Button {
                        learnRequest = LearnRequestItem(steps: unlearned)
                    } label: {
                        Label("Teach Input Buttons (\(unlearned.count))", systemImage: "list.number")
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
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(350))
                    learnRequest = LearnRequestItem(steps: steps)
                }
            }
        }
    }

    private func inputRow(_ step: LearnStep) -> some View {
        let action = step.action ?? ""
        let isLearned = learned(step)
        return Button {
            if isLearned {
                Task { await model.fire(targetId: currentItem.id, action: action) }
            } else {
                learnRequest = LearnRequestItem(steps: [step])
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: action == "prev_input" ? "chevron.left.circle" : action == "next_input" ? "chevron.right.circle" : "hifispeaker")
                    .foregroundStyle(isLearned ? Brand.accent : Brand.muted)
                    .frame(width: 24)
                Text(step.label).foregroundStyle(isLearned ? Brand.text : Brand.muted)
                Spacer()
                if isLearned {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Brand.ok)
                } else {
                    Text("Teach").font(.caption.weight(.semibold)).foregroundStyle(Brand.accent)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(model.isPerformingAction)
        .contextMenu {
            Button {
                learnRequest = LearnRequestItem(steps: [step])
            } label: {
                Label(isLearned ? "Re-learn" : "Teach", systemImage: "wand.and.stars")
            }
            if isLearned {
                Button(role: .destructive) {
                    Task { await model.unlearn(targetId: currentItem.id, action: action) }
                } label: {
                    Label("Forget Code", systemImage: "xmark.circle")
                }
            }
        }
    }
}
