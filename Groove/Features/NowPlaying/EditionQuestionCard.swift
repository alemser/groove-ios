import SwiftUI

/// "Which pressing is this?" — groove-identity#38.
///
/// Shown whenever more than one release in the library matches, unless there is
/// certainty about which it is — a track that exists on only one of them. The
/// amplifier's input and the detector's reading of the medium are hints: they
/// mark the likely option and say why, but they do not answer.
///
/// Guessing gets the cover, the year and the numbering wrong — the 1977 vinyl
/// runs A1-A5 / B1-B5 where the 2001 CD runs 1-12.
///
/// The answer locks the session onto that edition's tracklist. Dismissing keeps
/// whatever is showing, so the question is never a dead end. Catalog rows are
/// never moved.
struct EditionQuestionCard: View {
    let question: EditionQuestion
    let onChoose: (EditionOption) -> Void
    var onDismiss: (() -> Void)?

    @State private var answering: String?
    var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(EditionQuestion.heading)
                    .font(.headline)
                    .foregroundStyle(Brand.text)
                Text(question.albumLabel)
                    .font(.subheadline)
                    .foregroundStyle(Brand.muted)
            }

            ForEach(question.candidates) { option in
                Button {
                    answering = option.id
                    onChoose(option)
                } label: {
                    row(option)
                }
                .buttonStyle(.plain)
                .disabled(answering != nil)
                .opacity(answering == nil || answering == option.id ? 1 : 0.45)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(Brand.warn)
            } else {
                Text("More than one release in your library matches. Nothing here is certain enough to choose for you.")
                    .font(.footnote)
                    .foregroundStyle(Brand.muted)
            }

            // Without this the question blocks the screen until it is answered,
            // which locked the app for anyone happy with what was showing.
            if let onDismiss {
                Button("Keep what is showing", action: onDismiss)
                    .font(.footnote)
                    .foregroundStyle(Brand.muted)
                    .disabled(answering != nil)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Brand.teal.opacity(0.35), lineWidth: 1)
        )
        .onChange(of: question.key) { _, _ in
            answering = nil
        }
    }

    private func row(_ option: EditionOption) -> some View {
        HStack(spacing: 12) {
            Artwork(raw: option.artworkUrl, cornerRadius: 6)
                .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(headline(option))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Brand.text)
                    if option.suggested == true {
                        Text("LIKELY")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Brand.teal)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Brand.teal.opacity(0.16), in: Capsule())
                    }
                }
                if let detail = detail(option) {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(Brand.muted)
                }
            }
            Spacer(minLength: 8)
            if answering == option.id {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "chevron.right")
                    .font(.footnote)
                    .foregroundStyle(Brand.muted)
            }
        }
        .padding(10)
        .background(Brand.cardElevated, in: RoundedRectangle(cornerRadius: 10))
    }

    private func headline(_ option: EditionOption) -> String {
        [option.releaseFormat?.nonEmpty?.uppercased(), option.year?.nonEmpty]
            .compactMap { $0 }
            .joined(separator: " · ")
            .nonEmpty ?? "Edition"
    }

    /// Leads with where the recognised track sits on this edition. "This track
    /// is A1" reads as vinyl at a glance, which is usually how a human tells two
    /// pressings apart faster than by year.
    private func detail(_ option: EditionOption) -> String? {
        var bits: [String] = []
        if let position = option.position?.nonEmpty {
            bits.append("this track is \(position)")
        }
        if let count = option.tracklistCount, count > 0 {
            bits.append("\(count) tracks")
        }
        // The hint is named, not applied: the operator can see why the system
        // leans this way and overrule it, which is the point of not letting the
        // hint answer by itself.
        if option.suggested == true, let why = option.suggestedWhy?.nonEmpty {
            bits.append(why)
        }
        return bits.isEmpty ? nil : bits.joined(separator: " · ")
    }
}

/// The open question with its answers wired to the app's Now Playing model:
/// the one wiring every screen that shows the question uses.
struct EditionQuestionPrompt: View {
    let question: EditionQuestion

    @Environment(AppSettings.self) private var settings
    @Environment(NowPlayingModel.self) private var model

    var body: some View {
        EditionQuestionCard(question: question, onChoose: { option in
            Task { await model.chooseEdition(option, settings: settings) }
        }, onDismiss: {
            Task { await model.dismissEditionQuestion(settings: settings) }
        }, errorMessage: model.editionErrorMessage)
    }
}

/// Leads to the open question from the Library, where the operator may be
/// looking at the album rather than at Now Playing. It is about the record
/// playing now, so it exists only while the question is open: the parent shows
/// it for `NowPlayingModel.editionQuestion`, and when the answer closes the
/// question the banner, and the sheet it opened, go with it.
struct EditionQuestionBanner: View {
    let question: EditionQuestion

    @State private var showing = false

    var body: some View {
        BannerCard(
            systemImage: "opticaldisc",
            tint: Brand.teal,
            title: EditionQuestion.heading,
            subtitle: "\(question.albumLabel) · answer while it plays",
            accessibilityLabel: "Answer which pressing of \(question.albumLabel) is playing"
        ) { showing = true }
        .sheet(isPresented: $showing) {
            ScrollView {
                EditionQuestionPrompt(question: question)
                    .padding(20)
            }
            .grooveScreenBackground()
            .presentationDetents([.medium, .large])
        }
    }
}
