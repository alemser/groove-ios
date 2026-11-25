import SwiftUI

/// The update question or notice the app puts in front of the person when it
/// reaches a board (`UpdateCenter.notice`). Swiping it away is the same as
/// "Later" / "OK"; for the question it leaves the choice unanswered, and the app
/// asks again on the next connection.
struct UpdateNoticeSheet: View {
    let notice: UpdateNotice

    @Environment(UpdateCenter.self) private var updates
    @State private var choice = UpdatePreference.preselected
    @State private var sending = false

    var body: some View {
        NavigationStack {
            Form {
                switch notice {
                case .question:
                    Section {
                        UpdatePreferenceOptions(selection: choice) { choice = $0 }
                    }
                case let .available(_, notes, security):
                    Section {
                        if security {
                            SecurityFixBadge()
                        }
                        notesText(notes)
                    }
                case .installed, .failed:
                    Section {
                        notesText(notice.message)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .grooveScreenBackground()
            .navigationTitle(notice.title)
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) { actions.padding(20) }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func notesText(_ text: String) -> some View {
        Text(text.nonEmpty ?? "No release notes.")
            .font(.subheadline)
            .foregroundStyle(text.nonEmpty == nil ? Brand.muted : Brand.text)
    }

    @ViewBuilder
    private var actions: some View {
        switch notice {
        case .question:
            primaryButton("Continue") { _ = await updates.setPreference(choice) }
        case .available:
            HStack(spacing: 12) {
                Button {
                    updates.dismiss(notice)
                } label: {
                    Text("Later").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                primaryButton("Update") { await updates.approve() }
            }
        case .installed, .failed:
            primaryButton("OK") { updates.dismiss(notice) }
        }
    }

    /// The answer closes the sheet on its own: the status it brings back no longer
    /// calls for this notice.
    private func primaryButton(_ title: String, _ action: @escaping @MainActor () async -> Void) -> some View {
        Button {
            sending = true
            Task {
                await action()
                sending = false
            }
        } label: {
            Text(title).frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .disabled(sending)
    }
}
