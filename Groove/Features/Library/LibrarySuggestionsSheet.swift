import SwiftUI
import Observation

/// Albums the catalog recognized while playing but the library holds no
/// edition of (groove-catalog#24). The server never adds one by itself: each
/// suggestion offers a primary edition — the one the play was confirmed on,
/// else the best fit — plus ranked alternatives, and waits for the user to
/// add one, edit one first, or put it away.
@MainActor
@Observable
final class LibrarySuggestionsModel {
    var suggestions: [LibrarySuggestion] = []
    var phase: Phase = .loading
    /// `key(_:_:)` of the edition whose request is in flight.
    var busyKey: String?
    var actionError: String?
    /// A refused add the user may still force (tracklist warnings — never a
    /// missing duration, which has no override).
    var pendingForce: PendingForce?
    /// A draft copy to open in the editor ("Edit First").
    var forked: ForkedEdition?

    enum Phase: Equatable { case loading, loaded, error(String) }

    struct PendingForce: Identifiable {
        let suggestion: LibrarySuggestion
        let edition: LibrarySuggestionEdition
        let message: String
        var id: String { "\(suggestion.id)|\(edition.id)" }
    }

    struct ForkedEdition: Identifiable {
        let jobId: Int64
        let draft: PendingRelease
        var id: Int64 { jobId }
    }

    private var settings: AppSettings?
    /// Suggestions the user asked to see every alternative of.
    private var expanded: Set<Int64> = []

    func configure(_ settings: AppSettings) {
        if self.settings == nil {
            self.settings = settings
            Task { await load() }
        }
    }

    func key(_ suggestion: LibrarySuggestion, _ edition: LibrarySuggestionEdition) -> String {
        "\(suggestion.id)|\(edition.id)"
    }

    func load() async {
        guard let settings else { return }
        if suggestions.isEmpty { phase = .loading }
        let service = CatalogService(settings: settings)
        do {
            var list = try await service.librarySuggestions().suggestions
            // Expanded suggestions show every alternative. Supplementary: a
            // failure here keeps the capped list rather than failing the sheet.
            for index in list.indices where expanded.contains(list[index].id) && (list[index].moreAlternatives ?? 0) > 0 {
                if let full = try? await service.librarySuggestion(id: list[index].id, alternatives: 50) {
                    list[index] = full
                }
            }
            suggestions = list
            phase = .loaded
        } catch {
            if suggestions.isEmpty {
                phase = .error(error.localizedForDisplay)
            } else {
                actionError = error.localizedForDisplay
            }
        }
    }

    func showAllEditions(_ suggestion: LibrarySuggestion) async {
        expanded.insert(suggestion.id)
        await load()
    }

    func add(_ suggestion: LibrarySuggestion, _ edition: LibrarySuggestionEdition, force: Bool = false) async {
        guard let settings else { return }
        busyKey = key(suggestion, edition)
        defer { busyKey = nil }
        actionError = nil
        do {
            try await CatalogService(settings: settings).acceptLibrarySuggestion(id: suggestion.id, edition: edition, force: force)
            suggestions.removeAll { $0.id == suggestion.id }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch APIError.http(let status, let body) where status == 422 {
            let refusal = Self.decodeRefusal(body)
            let issues = (refusal?.preflightIssues ?? []).compactMap { $0.message?.nonEmpty }.joined(separator: "\n")
            let parts: [String?] = [refusal?.error?.nonEmpty ?? "The tracklist failed the release check.", issues.nonEmpty]
            let message = parts
                .compactMap { $0 }
                .joined(separator: "\n\n")
            if refusal?.forceable == false || force {
                actionError = message + "\n\nUse Edit First to fix the tracklist."
            } else {
                pendingForce = PendingForce(suggestion: suggestion, edition: edition, message: message)
            }
        } catch APIError.http(let status, _) where status == 409 {
            // Already added or put away elsewhere (the web Studio, another phone).
            await load()
        } catch {
            actionError = Self.message(for: error)
        }
    }

    /// Opens a draft copy of the edition in the editor. The suggestion stays
    /// until that copy is saved — saving it is what adds it to the library.
    func edit(_ suggestion: LibrarySuggestion, _ edition: LibrarySuggestionEdition) async {
        guard let settings else { return }
        busyKey = key(suggestion, edition)
        defer { busyKey = nil }
        actionError = nil
        do {
            let resp = try await CatalogService(settings: settings).forkLibrarySuggestion(id: suggestion.id, edition: edition)
            forked = ForkedEdition(jobId: resp.job.id, draft: resp.draft)
        } catch APIError.http(let status, _) where status == 409 {
            await load()
        } catch {
            actionError = Self.message(for: error)
        }
    }

    func dismiss(_ suggestion: LibrarySuggestion) async {
        guard let settings else { return }
        suggestions.removeAll { $0.id == suggestion.id }
        do {
            try await CatalogService(settings: settings).dismissLibrarySuggestion(id: suggestion.id)
        } catch {
            await load()
        }
    }

    private static func decodeRefusal(_ body: String) -> ConfirmPreflightError? {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try? decoder.decode(ConfirmPreflightError.self, from: Data(body.utf8))
    }

    /// These endpoints answer errors as `{"error": "…"}` — show the sentence,
    /// not the raw JSON `localizedForDisplay` would print.
    private static func message(for error: Error) -> String {
        if let apiError = error as? APIError, case let .http(_, body) = apiError,
           let text = decodeRefusal(body)?.error?.nonEmpty {
            return text
        }
        return error.localizedForDisplay
    }
}

/// Sheet for the "add to library" suggestions — presented from a banner in the
/// Library grid, like the association queue.
struct LibrarySuggestionsSheet: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @State private var model = LibrarySuggestionsModel()

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Add to Library")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { dismiss() }
                    }
                }
                .grooveScreenBackground()
        }
        .task { model.configure(settings) }
        .sheet(item: $model.forked, onDismiss: { Task { await model.load() } }) { forked in
            EditReleaseView(jobId: forked.jobId, edition: forked.draft)
        }
        .confirmationDialog(
            "Add anyway?",
            isPresented: Binding(
                get: { model.pendingForce != nil },
                set: { if !$0 { model.pendingForce = nil } }
            ),
            titleVisibility: .visible,
            presenting: model.pendingForce
        ) { pending in
            Button("Add Anyway") { Task { await model.add(pending.suggestion, pending.edition, force: true) } }
            Button("Edit First") { Task { await model.edit(pending.suggestion, pending.edition) } }
            Button("Cancel", role: .cancel) {}
        } message: { pending in
            Text(pending.message)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loading:
            LoadingView()
        case let .error(message):
            ErrorStateView(message: message) { Task { await model.load() } }
        case .loaded:
            if model.suggestions.isEmpty {
                EmptyStateView(icon: "checkmark.seal", title: "All caught up",
                               message: "Every album you've played is in your library or was put away.")
            } else {
                List {
                    if let err = model.actionError {
                        Section {
                            Text(err).font(.caption).foregroundStyle(Brand.err)
                        }
                        .listRowBackground(Brand.surface)
                    }
                    ForEach(model.suggestions) { suggestion in
                        Section {
                            rows(for: suggestion)
                        } header: {
                            header(suggestion)
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .refreshable { await model.load() }
            }
        }
    }

    private func header(_ suggestion: LibrarySuggestion) -> some View {
        let heard = suggestion.recognizedTracks?.count ?? 0
        return VStack(alignment: .leading, spacing: 2) {
            Text(suggestion.album)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Brand.text)
            Text("\(suggestion.artist) · \(heard) track\(heard == 1 ? "" : "s") heard")
                .font(.caption)
                .foregroundStyle(Brand.muted)
        }
        .textCase(nil)
    }

    @ViewBuilder
    private func rows(for suggestion: LibrarySuggestion) -> some View {
        if let primary = suggestion.primary {
            editionRow(suggestion, primary, isPrimary: true)
        }
        let alternatives = suggestion.alternatives ?? []
        if !alternatives.isEmpty {
            DisclosureGroup {
                ForEach(alternatives) { edition in
                    editionRow(suggestion, edition, isPrimary: false)
                }
                if let more = suggestion.moreAlternatives, more > 0 {
                    Button("Show \(more) More Edition\(more == 1 ? "" : "s")") {
                        Task { await model.showAllEditions(suggestion) }
                    }
                    .font(.subheadline)
                }
            } label: {
                Text("Other Editions (\(alternatives.count)\((suggestion.moreAlternatives ?? 0) > 0 ? "+" : ""))")
                    .font(.subheadline)
                    .foregroundStyle(Brand.text)
            }
            .listRowBackground(Brand.surface)
        }
        Button {
            Task { await model.dismiss(suggestion) }
        } label: {
            Text("Not Now")
                .font(.subheadline)
                .foregroundStyle(Brand.muted)
        }
        .listRowBackground(Brand.surface)
        .accessibilityHint("Leaves the library unchanged. This album won't be suggested again for the rest of the sitting.")
    }

    private func editionRow(_ suggestion: LibrarySuggestion, _ edition: LibrarySuggestionEdition, isPrimary: Bool) -> some View {
        let key = model.key(suggestion, edition)
        return SuggestionEditionRow(
            edition: edition,
            isPrimary: isPrimary,
            isBusy: model.busyKey == key,
            onAdd: { Task { await model.add(suggestion, edition) } },
            onEdit: { Task { await model.edit(suggestion, edition) } }
        )
        .disabled(model.busyKey != nil)
        .listRowBackground(Brand.surface)
    }
}

/// One candidate edition: enough to tell pressings apart (format, country,
/// year, label, track count, cover) and why it ranks where it does.
struct SuggestionEditionRow: View {
    let edition: LibrarySuggestionEdition
    let isPrimary: Bool
    let isBusy: Bool
    let onAdd: () -> Void
    let onEdit: () -> Void

    /// The server lists this first among the reasons; the row already says it
    /// in its own label.
    private static let confirmedReason = "edition the play was confirmed on"

    private var sourceLabel: String {
        switch edition.source.lowercased() {
        case "musicbrainz": return "MusicBrainz"
        case "discogs": return "Discogs"
        case "itunes": return "iTunes"
        default: return edition.source
        }
    }

    private var details: String {
        var parts: [String] = []
        if let country = edition.country?.nonEmpty { parts.append(country) }
        if let year = edition.year { parts.append(year) }
        if let label = edition.label?.nonEmpty { parts.append(label) }
        let total = edition.trackTotal ?? 0
        parts.append("\(total) track\(total == 1 ? "" : "s")")
        return parts.joined(separator: " · ")
    }

    private var reasons: String? {
        (edition.reasons ?? [])
            .filter { $0 != Self.confirmedReason }
            .joined(separator: " · ")
            .nonEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Artwork(raw: edition.artworkUrl, cornerRadius: 8)
                    .frame(width: isPrimary ? 64 : 44, height: isPrimary ? 64 : 44)
                VStack(alignment: .leading, spacing: 4) {
                    if isPrimary && edition.confirmed == true {
                        Text("Played as this edition")
                            .font(.caption2.weight(.semibold))
                            .textCase(.uppercase)
                            .tracking(0.4)
                            .foregroundStyle(Brand.teal)
                    }
                    Text(edition.album?.nonEmpty ?? "Untitled")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Brand.text)
                        .lineLimit(2)
                    HStack(spacing: 6) {
                        Badge(text: sourceLabel)
                        MediaFormatBadge(raw: edition.releaseFormat, labeled: true)
                    }
                    Text(details)
                        .font(.caption)
                        .foregroundStyle(Brand.muted)
                        .lineLimit(2)
                    if let reasons {
                        Text(reasons)
                            .font(.caption2)
                            .foregroundStyle(Brand.muted)
                            .italic()
                    }
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 10) {
                if isPrimary {
                    Button(action: onAdd) { addLabel }
                        .buttonStyle(.borderedProminent)
                        .tint(Brand.ok)
                } else {
                    Button(action: onAdd) { addLabel }
                        .buttonStyle(.bordered)
                        .tint(Brand.ok)
                }
                Button(action: onEdit) {
                    Label("Edit First", systemImage: "pencil")
                        .labelStyle(.iconOnly)
                        .font(.subheadline.weight(.semibold))
                        .frame(minHeight: 40)
                        .padding(.horizontal, 14)
                }
                .buttonStyle(.bordered)
                .tint(Brand.teal)
                .accessibilityLabel("Edit before adding")
            }
        }
        .padding(.vertical, 6)
    }

    private var addLabel: some View {
        Group {
            if isBusy {
                ProgressView()
            } else {
                Label(isPrimary ? "Add to Library" : "Use This", systemImage: "plus")
            }
        }
        .font(.subheadline.weight(.semibold))
        .frame(maxWidth: .infinity, minHeight: 40)
    }
}
