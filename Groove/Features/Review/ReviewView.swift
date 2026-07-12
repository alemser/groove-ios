import SwiftUI

struct ReviewView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(AttentionCenter.self) private var attention
    @State private var model = ReviewModel()

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Review")
                .navigationDestination(for: EnrichJob.self) { job in
                    EnrichJobDetailView(job: job)
                }
                .grooveScreenBackground()
        }
        .task {
            model.configure(settings)
            await attention.refresh()
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
            if model.associations.isEmpty && model.jobs.isEmpty {
                EmptyStateView(icon: "checkmark.seal", title: "All clear", message: "Nothing needs your attention right now.")
            } else {
                list
            }
        }
    }

    private var list: some View {
        List {
            if !model.associations.isEmpty {
                Section {
                    ForEach(model.associations) { item in
                        AssociationRowView(
                            item: item,
                            onAccept: { Task { await model.acceptSuggestion(item); await attention.refresh() } },
                            onDismiss: { Task { await model.dismiss(item); await attention.refresh() } }
                        )
                        .listRowBackground(Brand.surface)
                    }
                } header: {
                    Text("Needs Association (\(model.associations.count))")
                }
            }

            if !model.jobs.isEmpty {
                Section {
                    ForEach(model.jobs) { job in
                        NavigationLink(value: job) { EnrichJobRowView(job: job) }
                            .listRowBackground(Brand.surface)
                    }
                } header: {
                    Text("Enrich Jobs (\(model.jobs.count))")
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .refreshable { await model.load() }
    }
}

struct AssociationRowView: View {
    let item: PendingAssociation
    let onAccept: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.suggestedTitle?.nonEmpty ?? "Unidentified play")
                        .font(.body.weight(.medium)).foregroundStyle(Brand.text)
                    Text(item.suggestedArtist?.nonEmpty ?? item.failureReason?.humanizedReason ?? "No suggestion")
                        .font(.subheadline).foregroundStyle(Brand.muted)
                }
                Spacer()
                Text(Format.relative(item.startedAt)).font(.caption).foregroundStyle(Brand.muted)
            }
            HStack(spacing: 10) {
                if let tid = item.suggestedTrackId, tid > 0 {
                    Button(action: onAccept) {
                        Label("Accept", systemImage: "checkmark")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent).tint(Brand.ok)
                }
                Button(action: onDismiss) {
                    Label("Dismiss", systemImage: "xmark")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Brand.muted)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered).tint(Brand.muted)
            }
        }
        .padding(.vertical, 6)
    }
}

struct EnrichJobRowView: View {
    let job: EnrichJob

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(job.title?.nonEmpty ?? "Job #\(job.id)")
                    .font(.body.weight(.medium)).foregroundStyle(Brand.text).lineLimit(1)
                Text(job.artist?.nonEmpty ?? "—")
                    .font(.subheadline).foregroundStyle(Brand.muted).lineLimit(1)
            }
            Spacer(minLength: 4)
            EnrichStatusBadge(status: job.status)
        }
        .padding(.vertical, 2)
    }
}

struct EnrichStatusBadge: View {
    let status: String
    var body: some View {
        let (color, label): (Color, String) = switch status {
        case "complete": (Brand.ok, "Complete")
        case "failed": (Brand.err, "Failed")
        case "enriching": (Brand.teal, "Enriching")
        default: (Brand.warn, "Pending")
        }
        return Badge(text: label, color: color)
    }
}
