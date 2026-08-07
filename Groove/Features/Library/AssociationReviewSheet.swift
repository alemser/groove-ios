import SwiftUI
import Observation

@MainActor
@Observable
final class AssociationReviewModel {
    var associations: [PendingAssociation] = []
    var phase: Phase = .loading

    enum Phase: Equatable { case loading, loaded, error(String) }

    private var settings: AppSettings?

    func configure(_ settings: AppSettings) {
        if self.settings == nil {
            self.settings = settings
            Task { await load() }
        }
    }

    func load() async {
        guard let settings else { return }
        if associations.isEmpty { phase = .loading }
        do {
            associations = try await CatalogService(settings: settings).pendingAssociations().items
            phase = .loaded
        } catch {
            if associations.isEmpty {
                phase = .error((error as? APIError)?.localizedDescription ?? error.localizedDescription)
            }
        }
    }

    func acceptSuggestion(_ item: PendingAssociation) async {
        guard let settings, let trackId = item.suggestedTrackId, trackId > 0 else { return }
        associations.removeAll { $0.id == item.id }
        do {
            try await CatalogService(settings: settings).associatePlay(epoch: item.listenerEpoch, trackId: trackId)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            await load()
        }
    }

    func dismiss(_ item: PendingAssociation) async {
        guard let settings else { return }
        associations.removeAll { $0.id == item.id }
        do {
            try await CatalogService(settings: settings).dismissPendingAssociation(epoch: item.listenerEpoch)
        } catch {
            await load()
        }
    }
}

/// Sheet for the "needs association" queue — plays the recognizer couldn't (confidently)
/// match to a catalog track. Presented from a banner in the Library grid rather than
/// living in its own tab.
struct AssociationReviewSheet: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @State private var model = AssociationReviewModel()
    @State private var identifying: PendingAssociation?

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Needs Association")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { dismiss() }
                    }
                }
                .grooveScreenBackground()
        }
        .task { model.configure(settings) }
        .sheet(item: $identifying) { item in
            ManualIdentifySheet(
                epoch: item.listenerEpoch,
                seedArtist: item.suggestedArtist,
                seedTitle: item.suggestedTitle,
                seedAlbum: item.suggestedAlbum
            ) { Task { await model.load() } }
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
            if model.associations.isEmpty {
                EmptyStateView(icon: "checkmark.seal", title: "All clear", message: "No plays are waiting on an association right now.")
                    .task { dismiss() }
            } else {
                List {
                    ForEach(model.associations) { item in
                        AssociationRowView(
                            item: item,
                            onAccept: { Task { await model.acceptSuggestion(item) } },
                            onIdentify: { identifying = item },
                            onDismiss: { Task { await model.dismiss(item) } }
                        )
                        .listRowBackground(Brand.surface)
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .refreshable { await model.load() }
            }
        }
    }
}

struct AssociationRowView: View {
    let item: PendingAssociation
    let onAccept: () -> Void
    let onIdentify: () -> Void
    let onDismiss: () -> Void

    private var hasSuggestion: Bool { (item.suggestedTrackId ?? 0) > 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    if hasSuggestion {
                        Text("Suggested match")
                            .font(.caption2.weight(.semibold))
                            .textCase(.uppercase)
                            .tracking(0.4)
                            .foregroundStyle(Brand.teal)
                    }
                    Spacer()
                    if let count = item.playCount, count > 1 {
                        Text("Seen \(count)×")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Brand.muted)
                    }
                    Text(Format.relative(item.startedAt)).font(.caption).foregroundStyle(Brand.muted)
                }
                Text(item.suggestedTitle?.nonEmpty ?? "Unidentified play")
                    .font(.body.weight(.medium)).foregroundStyle(Brand.text)
                if hasSuggestion {
                    Text([item.suggestedArtist?.nonEmpty, item.suggestedAlbum?.nonEmpty].compactMap { $0 }.joined(separator: " · "))
                        .font(.subheadline).foregroundStyle(Brand.muted)
                } else {
                    Text(item.failureReason?.humanizedReason ?? "No suggestion")
                        .font(.subheadline).foregroundStyle(Brand.muted)
                }
                if let reason = item.suggestion?.reason?.humanizedReason {
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(Brand.muted)
                        .italic()
                }
            }
            HStack(spacing: 10) {
                if hasSuggestion {
                    Button(action: onAccept) {
                        Label("Accept", systemImage: "checkmark")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent).tint(Brand.ok)
                }
                if hasSuggestion {
                    Button(action: onIdentify) {
                        Label("Identify", systemImage: "magnifyingglass")
                            .labelStyle(.iconOnly)
                            .font(.subheadline.weight(.semibold))
                            .frame(minHeight: 44)
                            .padding(.horizontal, 14)
                    }
                    .buttonStyle(.bordered)
                    .tint(Brand.teal)
                    .accessibilityLabel("Identify manually")
                } else {
                    Button(action: onIdentify) {
                        Label("Identify", systemImage: "magnifyingglass")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Brand.teal)
                    .accessibilityLabel("Identify manually")
                }
                Button(action: onDismiss) {
                    Label("Dismiss", systemImage: "xmark")
                        .labelStyle(.iconOnly)
                        .font(.subheadline.weight(.semibold))
                        .frame(minHeight: 44)
                        .padding(.horizontal, 14)
                }
                .buttonStyle(.bordered).tint(Brand.muted)
                .accessibilityLabel("Dismiss")
            }
        }
        .padding(.vertical, 6)
    }
}
