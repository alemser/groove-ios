import SwiftUI

/// Live control: the day-to-day "use it" screen, as opposed to
/// Configuration (device attributes) or Equipment (teaching commands).
/// What's on it and where comes from the remote layout groove-rig keeps
/// (shared with the web remote, arranged via "Arrange"); against an older
/// groove-rig without layouts it falls back to fixed amplifier cards plus
/// one card per piece of equipment.
struct AmplifierRemoteTab: View {
    let model: AmplifierModel
    let equipmentModel: EquipmentRemoteModel
    @Environment(AppSettings.self) private var settings
    @State private var layoutModel = RemoteLayoutModel()
    @State private var stateModel = AmplifierStateModel()
    @State private var showResyncDialog = false
    @State private var showArrange = false

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                header
                if let layout = layoutModel.layout {
                    ForEach(layout.panels) { panel in
                        panelCard(panel)
                    }
                } else {
                    powerCard
                    inputCard
                    volumeCard
                    ForEach(remoteEquipment) { item in
                        equipmentCard(item)
                    }
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
        .overlay(alignment: .top) {
            if let hud = stateModel.hud {
                AmplifierHUDView(hud: hud)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3), value: stateModel.hud)
        .onAppear {
            stateModel.setInputs(model.amplifier?.inputs ?? [])
            stateModel.start(settings)
        }
        .onDisappear { stateModel.stop() }
        .onChange(of: model.amplifier?.inputs) { _, inputs in
            stateModel.setInputs(inputs ?? [])
        }
        .toolbar {
            if model.isPerformingAction {
                ToolbarItem(placement: .topBarTrailing) { ProgressView().tint(Brand.accent) }
            }
            if layoutModel.layout != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Arrange") { showArrange = true }
                }
            }
        }
        .task {
            layoutModel.configure(settings)
            await layoutModel.load()
        }
        // A button learned or removed elsewhere changes what the layout
        // holds (new buttons are appended server-side) — refetch.
        .onChange(of: equipmentModel.equipment) { _, _ in
            Task { await layoutModel.load() }
        }
        .sheet(isPresented: $showArrange, onDismiss: { Task { await layoutModel.load() } }) {
            ArrangeRemoteView(model: layoutModel, equipmentModel: equipmentModel)
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

    /// The amp's own reading when it has a state provider; otherwise the
    /// rig's inference from REC OUT level and its own IR history.
    private var powerState: String {
        stateModel.power?.rawValue ?? model.amplifier?.power?.state ?? "unknown"
    }
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
    // already says what this is, and without a state provider power.state
    // is a software inference with no hardware feedback (can be confidently
    // wrong after a physical remote/button press), so the button
    // deliberately never claims "Turn On"/"Turn Off" — it doesn't know which
    // way it's about to switch.
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
            inputControls
        }
        .padding(14)
        .grooveCard()
    }

    private var inputControls: some View {
        VStack(alignment: .leading, spacing: 12) {
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

            // An amp that reads its own input keeps groove-rig in step by
            // itself; resyncing by hand only matters without that reading.
            if stateModel.inputId == nil {
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
        }
    }

    /// The amp's own reading when it has one — an input changed with its
    /// own remote shows at once — named with the rig's label for that id;
    /// otherwise the input groove-rig tracks.
    private var currentInputLabel: String {
        if let id = stateModel.inputId, let input = model.amplifier?.inputs?.first(where: { $0.id == id }) {
            return input.label
        }
        return model.amplifier?.activeInputLabel?.nonEmpty ?? model.visibleInputs.first?.label ?? "Input"
    }

    // MARK: - Volume

    private var volumeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: "Volume")
            volumeControls
        }
        .padding(14)
        .grooveCard()
    }

    private var volumeControls: some View {
        HStack(spacing: 12) {
            Image(systemName: "speaker.wave.1.fill").foregroundStyle(Brand.muted).frame(width: 22)
            stepButton("minus", accessibilityLabel: "Volume down") { Task { await model.volume(direction: "down") } }
                .frame(maxWidth: .infinity)
            stepButton("plus", accessibilityLabel: "Volume up") { Task { await model.volume(direction: "up") } }
                .frame(maxWidth: .infinity)
            Image(systemName: "speaker.wave.3.fill").foregroundStyle(Brand.muted).frame(width: 22)
        }
    }

    // MARK: - Layout panels

    /// Unlearned buttons are left off — they do nothing here (teach them on
    /// the equipment's screen). The amplifier's power/input/volume always
    /// show, as before. A panel with nothing to show isn't drawn.
    private func isShown(_ c: RigLayoutControl) -> Bool {
        switch c.widget {
        case "input_select", "volume", "tone":
            return true
        case "power":
            return c.target == "amplifier" || resolvedPower(c.target) != nil
        default:
            return equipmentModel.isLearned(targetId: c.target, action: c.action ?? "")
        }
    }

    /// The one Power button's action: power_toggle if learned, else
    /// whichever of power_on/power_off is.
    private func resolvedPower(_ target: String) -> String? {
        ["power_toggle", "power_on", "power_off"].first { equipmentModel.isLearned(targetId: target, action: $0) }
    }

    @ViewBuilder
    private func panelCard(_ panel: RigLayoutPanel) -> some View {
        let controls = panel.controls.filter(isShown)
        if !controls.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel(text: panel.label)
                SpanGrid(columns: layoutModel.layout?.columns ?? 4) {
                    ForEach(controls) { c in
                        controlView(c).gridSpan(c.span)
                    }
                }
            }
            .padding(14)
            .grooveCard()
        }
    }

    @ViewBuilder
    private func controlView(_ c: RigLayoutControl) -> some View {
        switch c.widget {
        case "power":
            if c.target == "amplifier" {
                stateButton("Power", systemImage: "power", isActive: isOn, iconOnly: true) { Task { await model.togglePower() } }
                    .accessibilityLabel("Power")
            } else {
                remoteButton(c.label, icon: "power") {
                    if let action = resolvedPower(c.target) {
                        Task { await equipmentModel.fire(targetId: c.target, action: action) }
                    }
                }
            }
        case "input_select":
            inputControls
        case "volume":
            VStack(alignment: .leading, spacing: 6) {
                volumeControls
                toneCountdown
            }
        case "tone":
            toneControls
        default:
            remoteButton(c.label, icon: c.icon) {
                Task { await equipmentModel.fire(targetId: c.target, action: c.action ?? "") }
            }
        }
    }

    // MARK: - Tone (Bass/Treble key + Volume ±, e.g. the SP103)

    /// While the amp is in bass/treble mode its Volume ± adjusts that
    /// control, so groove-rig holds volume presses until the mode expires —
    /// say so, or a held volume tap just looks broken.
    private var toneCountdown: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            if let tone = model.activeTone(at: context.date) {
                Text("Volume keys are on \(tone.control) — back to volume in \(tone.seconds)s")
                    .font(.caption)
                    .foregroundStyle(Brand.warn)
            }
        }
    }

    private var toneControls: some View {
        let volumeOK = equipmentModel.isLearned(targetId: "amplifier", action: "volume_up")
            && equipmentModel.isLearned(targetId: "amplifier", action: "volume_down")
        return TimelineView(.periodic(from: .now, by: 1)) { context in
            let active = model.activeTone(at: context.date)?.control
            VStack(spacing: 8) {
                toneRow("bass", label: "Bass", icon: "dial.low", enabled: volumeOK, active: active == "bass")
                toneRow("treble", label: "Treble", icon: "dial.high", enabled: volumeOK, active: active == "treble")
            }
        }
    }

    private func toneRow(_ control: String, label: String, icon: String, enabled: Bool, active: Bool) -> some View {
        let learned = enabled && equipmentModel.isLearned(targetId: "amplifier", action: control)
        return HStack(spacing: 12) {
            Label(label, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(active ? Brand.accent : Brand.muted)
                .frame(width: 96, alignment: .leading)
            stepButton("minus", accessibilityLabel: "\(label) down") { Task { await model.tone(control: control, direction: "down") } }
                .frame(maxWidth: .infinity)
                .disabled(!learned)
            stepButton("plus", accessibilityLabel: "\(label) up") { Task { await model.tone(control: control, direction: "up") } }
                .frame(maxWidth: .infinity)
                .disabled(!learned)
        }
        .opacity(learned ? 1 : 0.45)
    }

    private func remoteButton(_ label: String, icon: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                if let icon {
                    Image(systemName: icon).font(.system(size: 15, weight: .semibold))
                }
                Text(label)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(Brand.cardElevated)
            .foregroundStyle(Brand.text)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(ScaleButtonStyle())
        .disabled(equipmentModel.isPerformingAction)
        .accessibilityLabel(label)
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

/// The remote's buttons fire IR at the amplifier, and an IR command has no
/// result on this screen by nature — what changes is across the room. So the
/// button is the only place confirmation can come from, and a 4% scale on a
/// 44pt control is under two points of movement.
///
/// The tap is confirmed on PRESS rather than on the reply. The round trip to
/// groove-rig and out to the amplifier takes long enough that waiting for it is
/// exactly what makes the button feel dead; by then the operator has already
/// pressed again. Failures are reported by the models, as `.error`.
private struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                guard pressed else { return }
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }
    }
}
