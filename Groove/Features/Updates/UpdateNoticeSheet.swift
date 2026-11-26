import SwiftUI

/// The update question or notice the app puts in front of the person when it
/// reaches a board (`UpdateCenter.notice`). Swiping it away is the same as
/// "Remind me tomorrow" for an available release and "OK" for an install's outcome;
/// for the question it leaves the choice unanswered, and the app asks again on the
/// next connection.
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
        // A swipe while an answer travels would send a second one.
        .interactiveDismissDisabled(sending)
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
            answerButton("Continue") { _ = await updates.setPreference(choice) }
        case let .available(_, _, security):
            VStack(spacing: 10) {
                answerButton("Update") { await updates.approve() }
                ForEach(UpdateReminder.choices(security: security), id: \.self) { reminder in
                    answerButton(reminder.title, prominent: false) { await updates.remind(reminder) }
                }
            }
        case .installed, .failed:
            answerButton("OK") { updates.dismiss(notice) }
        }
    }

    /// The answer closes the sheet on its own: the status it brings back no longer
    /// calls for this notice.
    @ViewBuilder
    private func answerButton(
        _ title: String,
        prominent: Bool = true,
        _ action: @escaping @MainActor () async -> Void
    ) -> some View {
        let button = Button {
            sending = true
            Task {
                await action()
                sending = false
            }
        } label: {
            Text(title).frame(maxWidth: .infinity)
        }
        .disabled(sending)
        if prominent {
            button.buttonStyle(.borderedProminent)
        } else {
            button.buttonStyle(.bordered)
        }
    }
}
