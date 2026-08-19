import SwiftUI

/// Live control: amplifier power/input/volume, plus a fire-button card per
/// piece of equipment that has a remote — the day-to-day "use it" screen,
/// as opposed to Configuration (device attributes) or Equipment (teaching
/// commands). Only reachable when there's actually something learned.
struct AmplifierRemoteTab: View {
    let model: AmplifierModel
    let equipmentModel: EquipmentRemoteModel
    @State private var showResyncDialog = false

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                header
                powerCard
                inputCard
                volumeCard
                ForEach(remoteEquipment) { item in
                    equipmentCard(item)
                }
                if let error = model.actionError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(Brand.err)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(16)
        }
        .toolbar {
            if model.isPerformingAction {
                ToolbarItem(placement: .topBarTrailing) { ProgressView().tint(Brand.accent) }
            }
        }
        .confirmationDialog(
            "Resync current physical input",
            isPresented: $showResyncDialog,
            titleVisibility: .visible
        ) {
            ForEach(model.visibleInputs) { input in
                Button(input.label) { Task { await model.resyncInput(id: input.id) } }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Use this when the amplifier input was changed physically (remote/front panel) so the app can realign before next/previous.")
        }
    }

    /// Only equipment that's both flagged for the remote *and* has at least
    /// one actually-learned command — an unlearned button is useless here,
    /// so a device with nothing learned yet doesn't get a card at all.
    private var remoteEquipment: [RigEquipmentItem] {
        equipmentModel.otherEquipment.filter { item in
            item.hasRemote && learnedActions(for: item).isEmpty == false
        }
    }

    private func learnedActions(for item: RigEquipmentItem) -> [String] {
        (item.actions ?? []).filter { equipmentModel.isLearned(targetId: item.id, action: $0) }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            let deviceLine = [model.amplifier?.maker, model.amplifier?.model]
                .compactMap { $0.nonEmpty }
                .joined(separator: "  ·  ")
            if !deviceLine.isEmpty {
                Text(deviceLine.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Brand.muted)
                    .tracking(0.5)
            }
            HStack(spacing: 5) {
                Circle().fill(powerColor).frame(width: 6, height: 6)
                Text(powerLabel).font(.caption2).foregroundStyle(Brand.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var powerState: String { model.amplifier?.power?.state ?? "unknown" }
    private var powerLabel: String { powerState.replacingOccurrences(of: "_", with: " ").capitalized }

    private var powerColor: Color {
        switch powerState {
        case "on", "warming_up": return Brand.ok
        case "standby": return Brand.warn
        default: return Brand.muted
        }
    }

    // MARK: - Power

    // Most amplifier remotes have a single physical power button — one
    // `power_toggle` IR code — not discrete on/off buttons. Mirrors the web
    // remote's single Power button rather than modeling hardware that
    // mostly doesn't exist. Icon-only: the "Power" section label above
    // already says what this is, and power.state is a software inference
    // with no hardware feedback (can be confidently wrong after a physical
    // remote/button press), so the button deliberately never claims
    // "Turn On"/"Turn Off" — it doesn't know which way it's about to switch.
    private var powerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: "Power")
            stateButton("Power", systemImage: "power", isActive: isOn, iconOnly: true) { Task { await model.togglePower() } }
                .accessibilityLabel("Power")
        }
        .padding(14)
        .grooveCard()
    }

    private var isOn: Bool { powerState == "on" || powerState == "warming_up" }

    // MARK: - Input

    /// Prev/Next only make sense for a cycle-mode amp (one relative
    /// next/prev-input IR code, stepped repeatedly) — a direct-mode amp like
    /// the Denon PMA-600NE has no such button on its remote at all, so
    /// showing these (even disabled) would be offering a control that can
    /// never mean anything. Mirrors remote.html's same check.
    private var cycleMode: Bool { (model.amplifier?.inputMode ?? "cycle") != "direct" }

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: "Input")
            HStack(spacing: 10) {
                if cycleMode {
                    navButton("chevron.left", accessibilityLabel: "Previous input") { Task { await model.prevInput() } }
                }
                Menu {
                    ForEach(model.visibleInputs) { input in
                        Button(input.label) { Task { await model.selectInput(id: input.id) } }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "hifispeaker.fill").foregroundStyle(Brand.accent)
                        Text(currentInputLabel).lineLimit(1).foregroundStyle(Brand.text)
                        Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundStyle(Brand.muted)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Brand.cardElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(model.isPerformingAction || model.visibleInputs.isEmpty)
                if cycleMode {
                    navButton("chevron.right", accessibilityLabel: "Next input") { Task { await model.nextInput() } }
                }
            }

            Button {
                showResyncDialog = true
            } label: {
                Label("Resync with physical input", systemImage: "arrow.triangle.2.circlepath")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Brand.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .disabled(model.isPerformingAction || model.visibleInputs.isEmpty)
        }
        .padding(14)
        .grooveCard()
    }

    private var currentInputLabel: String {
        model.amplifier?.activeInputLabel?.nonEmpty ?? model.visibleInputs.first?.label ?? "Input"
    }

    // MARK: - Volume

    private var volumeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: "Volume")
            HStack(spacing: 12) {
                Image(systemName: "speaker.wave.1.fill").foregroundStyle(Brand.muted).frame(width: 22)
                stepButton("minus", accessibilityLabel: "Volume down") { Task { await model.volume(direction: "down") } }
                    .frame(maxWidth: .infinity)
                stepButton("plus", accessibilityLabel: "Volume up") { Task { await model.volume(direction: "up") } }
                    .frame(maxWidth: .infinity)
                Image(systemName: "speaker.wave.3.fill").foregroundStyle(Brand.muted).frame(width: 22)
            }
        }
        .padding(14)
        .grooveCard()
    }

    // MARK: - Equipment

    private func equipmentCard(_ item: RigEquipmentItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: item.label)
            let columns = [GridItem(.adaptive(minimum: 96), spacing: 8)]
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(learnedActions(for: item), id: \.self) { action in
                    Button {
                        Task { await equipmentModel.fire(targetId: item.id, action: action) }
                    } label: {
                        Text(action.replacingOccurrences(of: "_", with: " ").capitalized)
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .background(Brand.cardElevated)
                            .foregroundStyle(Brand.text)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(ScaleButtonStyle())
                    .disabled(equipmentModel.isPerformingAction)
                }
            }
        }
        .padding(14)
        .grooveCard()
    }

    // MARK: - Buttons

    private func stateButton(
        _ title: String,
        systemImage: String,
        isActive: Bool,
        iconOnly: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Group {
                if iconOnly {
                    Label(title, systemImage: systemImage)
                        .labelStyle(.iconOnly)
                        .font(.title3.weight(.semibold))
                } else {
                    Label(title, systemImage: systemImage)
                        .labelStyle(.titleAndIcon)
                        .font(.subheadline.weight(.semibold))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 46)
                .background(isActive ? Brand.ok.opacity(0.15) : Brand.cardElevated)
                .foregroundStyle(isActive ? Brand.ok : Brand.text)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(isActive ? Brand.ok.opacity(0.35) : .clear, lineWidth: 1)
                )
        }
        .buttonStyle(ScaleButtonStyle())
        .disabled(model.isPerformingAction)
    }

    private func navButton(_ systemImage: String, accessibilityLabel: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Brand.text)
                .frame(width: 44, height: 44)
                .background(Brand.cardElevated)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(ScaleButtonStyle())
        .disabled(model.isPerformingAction)
        .accessibilityLabel(accessibilityLabel)
    }

    private func stepButton(_ systemImage: String, accessibilityLabel: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Brand.text)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(Brand.cardElevated)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(ScaleButtonStyle())
        .disabled(model.isPerformingAction)
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}
