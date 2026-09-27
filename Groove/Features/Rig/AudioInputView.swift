import SwiftUI

/// How Oceano is wired to the amplifier, and — on a line / pre out whose
/// level follows the volume knob — calibrating the input gain against a live
/// meter so recognition sees the level it was tuned for.
struct AudioInputView: View {
    @Environment(AppSettings.self) private var settings
    @State private var model = AudioInputModel()

    var body: some View {
        Form {
            switch model.phase {
            case .loading:
                Section {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }
            case .error(let message):
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Couldn't reach the audio input.")
                            .foregroundStyle(Brand.text)
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(Brand.muted)
                    }
                }
            case .loaded:
                if let level = model.level {
                    connectionSection
                    if level.inputLevel == .variable {
                        calibrationSection(level)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .grooveScreenBackground()
        .navigationTitle("Audio Input")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { model.start(settings) }
        .onDisappear { model.stop() }
        .alert("Couldn't apply", isPresented: Binding(
            get: { model.actionError != nil },
            set: { if !$0 { model.actionError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.actionError ?? "")
        }
    }

    private var connectionSection: some View {
        Section {
            Toggle("Variable line output", isOn: Binding(
                get: { model.isVariable },
                set: { variable in Task { await model.setVariable(variable) } }
            ))
            .tint(Brand.teal)
        } footer: {
            Text("For a line or pre out that follows your amplifier's volume. Leave off for REC OUT or Tape Out. Each setting keeps its own input gain.")
                .foregroundStyle(Brand.muted)
        }
    }

    private func calibrationSection(_ level: CaptureLevel) -> some View {
        let programme = level.programme
        return Section {
            VStack(alignment: .leading, spacing: 10) {
                Text("Play music at your usual volume and bring the level into the green.")
                    .font(.subheadline)
                    .foregroundStyle(Brand.text)
                LevelMeterView(programme: programme, previewRMS: model.previewRMS)
                HStack(alignment: .firstTextBaseline) {
                    Text(programme.band.title)
                        .font(.headline)
                        .foregroundStyle(programme.band.color)
                    Spacer()
                    Text(measuringCaption(level))
                        .font(.caption)
                        .foregroundStyle(Brand.muted)
                }
                Text(guidance(level))
                    .font(.footnote)
                    .foregroundStyle(Brand.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 4)

            if let gain = level.gain {
                if model.suggestedStep != nil {
                    suggestionButton
                }
                gainRow(gain)
            } else {
                Text("This capture device has no adjustable gain.")
                    .foregroundStyle(Brand.muted)
            }
        } header: {
            Text("Calibration")
        } footer: {
            Text("After each change Oceano briefly re-learns the silence between tracks.")
                .foregroundStyle(Brand.muted)
        }
    }

    /// One tap to the level the detector computed from what is playing now.
    private var suggestionButton: some View {
        Button {
            model.applySuggestion()
        } label: {
            HStack {
                Image(systemName: "wand.and.stars")
                Text("Set suggested gain")
                Spacer()
                if let delta = model.suggestedDeltaDB {
                    Text(String(format: "%+.1f dB", delta))
                        .monospacedDigit()
                }
            }
            .font(.body.weight(.semibold))
        }
        .foregroundStyle(Brand.teal)
        .disabled(model.pendingStep != nil)
    }

    private func gainRow(_ gain: CaptureGain) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Input gain")
                    .foregroundStyle(Brand.text)
                Text(gainCaption(gain))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Brand.muted)
            }
            Spacer()
            if model.isApplying || model.pendingStep != nil {
                ProgressView()
            }
            stepButton("minus", enabled: model.canStepDown) { model.nudge(-1) }
                .accessibilityLabel("Lower input gain")
            stepButton("plus", enabled: model.canStepUp) { model.nudge(1) }
                .accessibilityLabel("Raise input gain")
        }
    }

    private func stepButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .frame(width: 36, height: 36)
                .background(Brand.cardElevated, in: Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(enabled ? Brand.teal : Brand.muted)
        .disabled(!enabled)
    }

    private func gainCaption(_ gain: CaptureGain) -> String {
        let step = model.displayedStep ?? gain.step
        var caption = "Step \(step) of \(gain.maxStep)"
        if let db = model.displayedDB {
            caption += String(format: " · %+.1f dB", db)
        }
        return caption
    }

    private func measuringCaption(_ level: CaptureLevel) -> String {
        let p = level.programme
        if p.band == .unknown {
            return String(format: "%.0f of %.0f s", min(p.seconds, p.minSeconds), p.minSeconds)
        }
        return String(format: "over %.0f s", p.seconds)
    }

    /// The meter reads everything that arrives, so a low reading with the
    /// gate still closed means either nothing is playing or the music is too
    /// quiet to be heard at all — the case calibration exists for.
    private func guidance(_ level: CaptureLevel) -> String {
        let band = level.programme.band
        if !level.isPlaying, band == .tooLow || band == .low {
            return "No music detected. If something is playing, it's too quiet for Oceano to hear — raise the input gain."
        }
        return band.guidance
    }
}
