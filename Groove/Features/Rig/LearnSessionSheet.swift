import SwiftUI

/// Guided IR-learn flow: start a session, ask the user to press the remote
/// button, and poll until `groove-rig` confirms the code was captured.
struct LearnSessionSheet: View {
    let targetId: String
    let action: String
    var onLearned: () -> Void = {}

    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @State private var model = LearnSessionModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Spacer()
                icon
                Text(title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Brand.text)
                    .multilineTextAlignment(.center)
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
            .navigationTitle("Teach “\(actionTitle)”")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        model.cancel()
                        dismiss()
                    }
                }
            }
        }
        .task {
            model.configure(settings)
            model.start(targetId: targetId, action: action)
        }
    }

    private var actionTitle: String {
        action.replacingOccurrences(of: "_", with: " ").capitalized
    }

    @ViewBuilder
    private var icon: some View {
        switch model.state {
        case .success:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(Brand.ok)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(Brand.err)
        case .idle, .starting, .running:
            ProgressView()
                .controlSize(.large)
                .tint(Brand.accent)
        }
    }

    private var title: String {
        switch model.state {
        case .idle, .starting: return "Getting ready…"
        case .running: return "Point the remote at the Pi and press the button"
        case .success: return "Learned!"
        case .failed: return "Couldn't learn the code"
        }
    }

    private var subtitle: String {
        switch model.state {
        case .idle, .starting: return ""
        case .running: return "Hold the button steady until this screen updates."
        case .success: return "This command is ready to use."
        case .failed(let message): return message
        }
    }

    @ViewBuilder
    private var footer: some View {
        switch model.state {
        case .success:
            Button("Done") {
                onLearned()
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .tint(Brand.accent)
        case .failed:
            Button("Try Again") {
                model.start(targetId: targetId, action: action)
            }
            .buttonStyle(.borderedProminent)
            .tint(Brand.accent)
        case .idle, .starting, .running:
            EmptyView()
        }
    }
}
