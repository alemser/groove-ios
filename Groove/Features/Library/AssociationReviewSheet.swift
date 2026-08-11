import SwiftUI
import Observation

/// One release-shaped bucket of pending items — the iOS counterpart to the web
/// pending panel's `findGroupForPending`/orphan-group split. `key` is stable
/// across reloads so `List` diffing doesn't reshuffle rows on every poll.
struct PendingAssociationGroup: Identifiable {
    let key: String
    let title: String
    let subtitle: String?
    var items: [PendingAssociation]
    var id: String { key }

    var confirmableItems: [PendingAssociation] { items.filter { ($0.suggestedTrackId ?? 0) > 0 } }
}

private let orphanGroupKey = "__unlinked__"

@MainActor
@Observable
final class AssociationReviewModel {
    var associations: [PendingAssociation] = []
    var phase: Phase = .loading
    var bulkBusy = false

    enum Phase: Equatable { case loading, loaded, error(String) }

    private var settings: AppSettings?

    /// Grouped by suggested release, with everything lacking a suggestion
    /// bucketed into "Unlinked plays" — mirrors `catalog-studio.html`'s
    /// `findGroupForPending`/`buildOrphanPendingGroup`.
    var groups: [PendingAssociationGroup] {
        var order: [String] = []
        var buckets: [String: PendingAssociationGroup] = [:]
        for item in associations {
            let hasSuggestion = (item.suggestedTrackId ?? 0) > 0
            let key = hasSuggestion ? "\(item.suggestedArtist ?? "")|\(item.suggestedAlbum ?? "")" : orphanGroupKey
            if buckets[key] == nil {
                order.append(key)
                let title = hasSuggestion ? (item.suggestedAlbum?.nonEmpty ?? item.suggestedArtist?.nonEmpty ?? "Suggested match") : "Unlinked plays"
                let subtitle = hasSuggestion ? item.suggestedArtist?.nonEmpty : nil
                buckets[key] = PendingAssociationGroup(key: key, title: title, subtitle: subtitle, items: [])
            }
            buckets[key]?.items.append(item)
        }
        return order.compactMap { buckets[$0] }
    }

    var confirmableCount: Int { associations.filter { ($0.suggestedTrackId ?? 0) > 0 }.count }

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
            try await CatalogService(settings: settings).confirmProgrammeSuggestion(epoch: item.listenerEpoch)
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

    /// "Confirm All" for a group or the whole queue — only items carrying a
    /// suggestion can be confirmed (no bulk endpoint server-side, web loops
    /// client-side the same way).
    func confirmAll(_ items: [PendingAssociation]) async {
        guard let settings else { return }
        let suggested = items.filter { ($0.suggestedTrackId ?? 0) > 0 }
        guard !suggested.isEmpty else { return }
        bulkBusy = true
        associations.removeAll { item in suggested.contains { $0.id == item.id } }
        let service = CatalogService(settings: settings)
        await withTaskGroup(of: Void.self) { group in
            for item in suggested {
                group.addTask { try? await service.confirmProgrammeSuggestion(epoch: item.listenerEpoch) }
            }
        }
        bulkBusy = false
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    func dismissAll(_ items: [PendingAssociation]) async {
        guard let settings, !items.isEmpty else { return }
        bulkBusy = true
        associations.removeAll { item in items.contains { $0.id == item.id } }
        let service = CatalogService(settings: settings)
        await withTaskGroup(of: Void.self) { group in
            for item in items {
                group.addTask { try? await service.dismissPendingAssociation(epoch: item.listenerEpoch) }
            }
        }
        bulkBusy = false
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
                    if model.associations.count > 1 {
                        Section {
                            bulkBar(
                                count: model.associations.count,
                                confirmableCount: model.confirmableCount,
                                onConfirmAll: { Task { await model.confirmAll(model.associations) } },
                                onDismissAll: { Task { await model.dismissAll(model.associations) } }
                            )
                        }
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                    }
                    ForEach(model.groups) { group in
                        Section {
                            ForEach(group.items) { item in
                                AssociationRowView(
                                    item: item,
                                    onAccept: { Task { await model.acceptSuggestion(item) } },
                                    onIdentify: { identifying = item },
                                    onDismiss: { Task { await model.dismiss(item) } }
                                )
                                .listRowBackground(Brand.surface)
                            }
                        } header: {
                            groupHeader(group)
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .refreshable { await model.load() }
                .disabled(model.bulkBusy)
            }
        }
    }

    private func bulkBar(count: Int, confirmableCount: Int, onConfirmAll: @escaping () -> Void, onDismissAll: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Text("\(count) waiting").font(.subheadline.weight(.semibold)).foregroundStyle(Brand.text)
            Spacer()
            if confirmableCount > 0 {
                Button("Confirm All (\(confirmableCount))", action: onConfirmAll)
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.bordered)
                    .tint(Brand.ok)
            }
            Button("Dismiss All", role: .destructive, action: onDismissAll)
                .font(.caption.weight(.semibold))
                .buttonStyle(.bordered)
                .tint(Brand.muted)
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func groupHeader(_ group: PendingAssociationGroup) -> some View {
        if group.items.count > 1 {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(group.title)
                    if let subtitle = group.subtitle {
                        Text(subtitle).textCase(nil)
                    }
                }
                Spacer()
                if !group.confirmableItems.isEmpty {
                    Button("Confirm All") { Task { await model.confirmAll(group.items) } }
                        .font(.caption2.weight(.semibold))
                        .buttonStyle(.borderless)
                }
                Button("Dismiss All") { Task { await model.dismissAll(group.items) } }
                    .font(.caption2.weight(.semibold))
                    .buttonStyle(.borderless)
                    .tint(Brand.muted)
            }
        } else {
            Text(group.title)
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
