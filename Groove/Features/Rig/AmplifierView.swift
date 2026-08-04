import SwiftUI

/// Live control for the amplifier: power, input, and volume — proxied through
/// `groove-catalog` to `groove-rig`'s target dispatcher. IR codes themselves
/// are taught separately in Equipment & Remote.
struct AmplifierView: View {
    @Environment(AppSettings.self) private var settings
    @State private var model = AmplifierModel()
    @State private var showResyncDialog = false

    var body: some View {
        Group {
            switch model.phase {
            case .loading:
                LoadingView(label: "Loading amplifier…")
            case .error(let message):
                ErrorStateView(message: message) { Task { await model.load() } }
            case .loaded:
                content
            }
        }
        .navigationTitle("Amplifier")
        .navigationBarTitleDisplayMode(.inline)
        .grooveScreenBackground()
        .task { model.configure(settings) }
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

    private var content: some View {
        ScrollView {
            VStack(spacing: 14) {
                header
                if !hasAnyLearnedAction {
                    setupHint
                }
                powerCard
                inputCard
                volumeCard
                if let error = model.actionError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(Brand.err)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(16)
        }
    }

    private var hasAnyLearnedAction: Bool {
        model.amplifierTarget?.actions.values.contains { $0.learned } ?? false
    }

    private var setupHint: some View {
        Label("No commands learned yet — set them up in Rig → Equipment & Remote.", systemImage: "wand.and.stars")
            .font(.footnote)
            .foregroundStyle(Brand.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
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

    private var powerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: "Power")
            HStack(spacing: 10) {
                stateButton("ON", systemImage: "power", isActive: isOn) { Task { await model.powerOn() } }
                stateButton("OFF", systemImage: "power", isActive: isOff) { Task { await model.powerOff() } }
            }
        }
        .padding(14)
        .grooveCard()
    }

    private var isOn: Bool { powerState == "on" || powerState == "warming_up" }
    private var isOff: Bool { powerState == "off" || powerState == "standby" }

    // MARK: - Input

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: "Input")
            HStack(spacing: 10) {
                navButton("chevron.left", accessibilityLabel: "Previous input") { Task { await model.prevInput() } }
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
                navButton("chevron.right", accessibilityLabel: "Next input") { Task { await model.nextInput() } }
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

    // MARK: - Buttons

    private func stateButton(
        _ title: String,
        systemImage: String,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
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
