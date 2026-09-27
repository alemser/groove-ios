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
            Text("Turn this on if Oceano is connected to a line or pre out whose level follows your amplifier's volume knob. Leave it off for a fixed-level REC OUT or Tape Out. Each setting keeps its own input gain, so switching back restores the gain you had before.")
                .foregroundStyle(Brand.muted)
        }
    }

    private func calibrationSection(_ level: CaptureLevel) -> some View {
        let programme = level.programme
        return Section {
            Text("Play music at the volume you usually listen at, then adjust the input gain until the meter sits in the green.")
                .font(.subheadline)
                .foregroundStyle(Brand.text)

            VStack(alignment: .leading, spacing: 10) {
                LevelMeterView(programme: programme)
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
            }
            .padding(.vertical, 4)

            if let gain = level.gain {
                gainRow(gain)
            } else {
                Text("This capture device has no adjustable gain.")
                    .foregroundStyle(Brand.muted)
            }
        } header: {
            Text("Calibration")
        } footer: {
            Text("Each change restarts the measurement and briefly re-learns the silence between tracks — step a few times, then let the meter settle.")
                .foregroundStyle(Brand.muted)
        }
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
        // dB is only known for the applied step, not one still pending.
        if model.pendingStep == nil, let db = gain.db {
            caption += String(format: " · %+.1f dB", db)
        }
        return caption
    }

    private func measuringCaption(_ level: CaptureLevel) -> String {
        let p = level.programme
        if p.band == .unknown {
            return String(format: "%.0f of %.0f s", min(p.seconds, p.minSeconds), p.minSeconds)
        }
        return String(format: "last %.0f s", p.seconds)
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
