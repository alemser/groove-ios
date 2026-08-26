import SwiftUI

/// "Which pressing is this?" — groove-identity#38.
///
/// Shown only when the system could not settle it on evidence. A track
/// exclusive to one edition, the detector's acoustic reading of the medium, or
/// a previously remembered answer all resolve it silently. What reaches here is
/// the genuinely ambiguous case, where guessing gets the cover, the year and the
/// track numbering wrong — the 1977 vinyl numbers sides A1-A5 / B1-B5 where the
/// 2001 CD runs 1-12.
///
/// The answer locks the session onto that edition's tracklist and is remembered
/// for the album. Catalog rows are never moved.
struct EditionQuestionCard: View {
    let question: EditionQuestion
    let onChoose: (EditionOption) -> Void

    @State private var answering: String?
    var errorMessage: String?

    private var albumLabel: String {
        [question.artist, question.album]
            .compactMap { $0?.nonEmpty }
            .joined(separator: " — ")
            .nonEmpty ?? "this album"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Which pressing is playing?")
                    .font(.headline)
                    .foregroundStyle(Brand.text)
                Text(albumLabel)
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
                Text("More than one edition in your library holds this track. The answer is remembered for this album.")
                    .font(.footnote)
                    .foregroundStyle(Brand.muted)
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
                Text(headline(option))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Brand.text)
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
        return bits.isEmpty ? nil : bits.joined(separator: " · ")
    }
}
