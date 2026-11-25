import SwiftUI

/// The two answers to "automatic or ask first", one row each with a check on
/// the chosen one: the first-use question and Settings → Updates draw the same rows.
struct UpdatePreferenceOptions: View {
    let selection: UpdatePreference?
    let choose: (UpdatePreference) -> Void

    var body: some View {
        ForEach(UpdatePreference.choices) { choice in
            Button {
                choose(choice)
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(choice.title).foregroundStyle(Brand.text)
                        Text(choice.subtitle).font(.caption).foregroundStyle(Brand.muted)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: selection == choice ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selection == choice ? Brand.accent : Brand.muted)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(selection == choice ? .isSelected : [])
        }
    }
}

/// Marks a release that carries a security fix, in its notice and in Settings.
struct SecurityFixBadge: View {
    var body: some View {
        Badge(text: "Security fix", color: Brand.warn)
    }
}
