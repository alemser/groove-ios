import SwiftUI

/// Guided IR-learn flow: ask the user to press a remote button and wait for
/// groove-rig to capture it. With several steps it's "Teach the Remote":
/// one button after another, with Skip for ones this remote doesn't have.
struct LearnSessionSheet: View {
    let targetId: String
    let equipmentLabel: String
    let steps: [LearnStep]
    /// Names other buttons on this target, for the duplicate warning.
    var labelFor: (String) -> String = { $0.replacingOccurrences(of: "_", with: " ").capitalized }
    var onFinished: () -> Void = {}

    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @State private var model = LearnSessionModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if model.isWalkthrough, model.state != .finished {
                    ProgressView(value: Double(model.index), total: Double(max(steps.count, 1)))
                        .tint(Brand.accent)
                        .padding(.horizontal, 28)
                    Text("\(min(model.index + 1, steps.count)) of \(steps.count)")
                        .font(.caption)
                        .foregroundStyle(Brand.muted)
                }
                Spacer()
                icon
                Text(title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Brand.text)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(Brand.muted)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                }
                Spacer()
                footer
            }
            .padding(.bottom, 24)
            .grooveScreenBackground()
            .navigationTitle(model.isWalkthrough ? "Teach the Remote" : "Teach “\(steps.first?.label ?? "")”")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(model.state == .finished || model.state == .success ? "Done" : "Cancel") { close() }
                }
            }
        }
        .interactiveDismissDisabled(model.state == .running)
        .task {
            model.configure(settings)
            model.begin(targetId: targetId, steps: steps)
        }
    }

    private func close() {
        model.cancel()
        onFinished()
        dismiss()
    }

    private var buttonName: String { model.current?.label ?? "" }

    @ViewBuilder
    private var icon: some View {
        switch model.state {
        case .success, .finished:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(Brand.ok)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(Brand.err)
        case .duplicate:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 52))
                .foregroundStyle(Brand.warn)
        case .idle, .starting, .running:
            ProgressView()
                .controlSize(.large)
                .tint(Brand.accent)
        }
    }

    private var title: String {
        switch model.state {
        case .idle, .starting: return "Getting ready…"
        case .running: return "Press “\(buttonName)” on the \(equipmentLabel) remote"
        case .success: return "Learned “\(buttonName)”"
        case .failed: return "Didn’t catch “\(buttonName)”"
        case .duplicate(let dups):
            return "“\(buttonName)” sent the same code as \(dups.map(labelFor).joined(separator: ", "))"
        case .finished:
            return model.learnedCount == 1 ? "Learned 1 button" : "Learned \(model.learnedCount) buttons"
        }
    }

    private var subtitle: String {
        switch model.state {
        case .idle, .starting: return ""
        case .running: return "Point it at the IR bridge and hold the button until this screen updates."
        case .success: return "It’s on the remote now."
        case .failed(let message): return message
        case .duplicate:
            return "Usually that means the wrong button was pressed. Some remotes really do share a code (one button for play and pause) — then keep it."
        case .finished: return model.learnedCount == 0 ? "Nothing was added." : "They’re on the remote now."
        }
    }

    @ViewBuilder
    private var footer: some View {
        VStack(spacing: 12) {
            switch model.state {
            case .success, .finished:
                Button("Done") { close() }
                    .buttonStyle(.borderedProminent)
                    .tint(Brand.accent)
            case .failed:
                Button("Try Again") { model.retry() }
                    .buttonStyle(.borderedProminent)
                    .tint(Brand.accent)
                if model.isWalkthrough { Button("Skip") { model.skip() } }
            case .duplicate:
                Button("Learn It Again") { model.retry() }
                    .buttonStyle(.borderedProminent)
                    .tint(Brand.accent)
                Button("Keep It") {
                    if model.isWalkthrough { model.keep() } else { close() }
                }
            case .running:
                if model.isWalkthrough {
                    HStack(spacing: 24) {
                        Button("Skip") { model.skip() }
                        Button("Stop", role: .destructive) { model.stop() }
                    }
                }
            case .idle, .starting:
                EmptyView()
            }
        }
    }
}
