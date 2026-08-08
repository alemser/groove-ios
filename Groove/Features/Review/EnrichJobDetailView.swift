import SwiftUI
import Observation

@MainActor
@Observable
final class EnrichJobDetailModel {
    var detail: EnrichJobDetail?
    var phase: Phase = .loading
    var busyReleaseId: Int64?
    var actionError: String?

    enum Phase: Equatable { case loading, loaded, error(String) }

    let jobId: Int64
    let trackId: Int64?
    private var settings: AppSettings?

    init(jobId: Int64, trackId: Int64?) {
        self.jobId = jobId
        self.trackId = trackId
    }

    func configure(_ settings: AppSettings) {
        if self.settings == nil { self.settings = settings; Task { await load() } }
    }

    func load() async {
        guard let settings else { return }
        if detail == nil { phase = .loading }
        do {
            detail = try await CatalogService(settings: settings).enrichJob(id: jobId)
            phase = .loaded
        } catch {
            if detail == nil { phase = .error((error as? APIError)?.localizedDescription ?? error.localizedDescription) }
        }
    }

    func confirm(_ release: PendingRelease) async {
        guard let settings else { return }
        busyReleaseId = release.id
        do {
            _ = try await CatalogService(settings: settings).confirmRelease(id: release.id)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            await load()
        } catch {
            actionError = (error as? APIError)?.localizedDescription ?? error.localizedDescription
        }
        busyReleaseId = nil
    }

    func discard(_ release: PendingRelease) async {
        guard let settings else { return }
        busyReleaseId = release.id
        if var d = detail { d.releases?.removeAll { $0.id == release.id }; detail = d }
        do {
            try await CatalogService(settings: settings).discardRelease(id: release.id)
        } catch {
            await load()
        }
        busyReleaseId = nil
    }

    /// Deletes the underlying track outright — for when none of the
    /// candidates (or lack thereof) are worth keeping around.
    func deleteTrack() async -> Bool {
        guard let settings, let trackId else { return false }
        do {
            try await CatalogService(settings: settings).deleteTrack(id: trackId)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            return true
        } catch {
            actionError = (error as? APIError)?.localizedDescription ?? error.localizedDescription
            return false
        }
    }
}

struct EnrichJobDetailView: View {
    let job: EnrichJob
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @State private var model: EnrichJobDetailModel
    @State private var showDeleteConfirm = false

    init(job: EnrichJob) {
        self.job = job
        _model = State(initialValue: EnrichJobDetailModel(jobId: job.id, trackId: job.trackId))
    }

    var body: some View {
        content
            .grooveScreenBackground()
            .navigationTitle("Release Candidates")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if model.trackId != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(role: .destructive) { showDeleteConfirm = true } label: {
                            Image(systemName: "trash")
                        }
                        .accessibilityLabel("Delete track")
                    }
                }
            }
            .confirmationDialog("Delete this track from the catalog?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    Task { if await model.deleteTrack() { dismiss() } }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Plays are detached and enrich jobs cleaned up. This can't be undone.")
            }
            .task { model.configure(settings) }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loading: LoadingView()
        case let .error(message): ErrorStateView(message: message) { Task { await model.load() } }
        case .loaded:
            ScrollView {
                VStack(spacing: 16) {
                    jobHeader
                    let j = model.detail?.job ?? job
                    let releases = model.detail?.releases ?? []
                    if releases.isEmpty {
                        EmptyStateView(
                            icon: emptyIcon(for: j.status),
                            title: emptyTitle(for: j.status),
                            message: emptyMessage(for: j)
                        )
                        .frame(height: 240)
                    } else {
                        ForEach(releases) { release in
                            ReleaseCandidateCard(
                                release: release,
                                busy: model.busyReleaseId == release.id,
                                onConfirm: { Task { await model.confirm(release) } },
                                onDiscard: { Task { await model.discard(release) } }
                            )
                        }
                    }
                    if let err = model.actionError {
                        Text(err).font(.caption).foregroundStyle(Brand.err)
                    }
                }
                .padding()
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
            .refreshable { await model.load() }
        }
    }

    private var jobHeader: some View {
        let j = model.detail?.job ?? job
        return VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(j.title?.nonEmpty ?? "Job #\(j.id)").font(.title3.bold()).foregroundStyle(Brand.text)
                Text(j.artist?.nonEmpty ?? "—").font(.subheadline).foregroundStyle(Brand.teal)
            }
            Divider().overlay(Brand.border)
            HStack(spacing: 8) {
                Text("Job status").font(.caption).foregroundStyle(Brand.muted)
                EnrichStatusBadge(status: j.status)
                Spacer(minLength: 0)
                if let isrc = j.isrc?.nonEmpty { Badge(text: isrc, color: Brand.muted) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Brand.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func emptyIcon(for status: String) -> String {
        switch status {
        case "pending": return "hourglass"
        case "enriching": return "arrow.triangle.2.circlepath"
        case "failed": return "exclamationmark.triangle"
        default: return "tray"
        }
    }

    private func emptyTitle(for status: String) -> String {
        switch status {
        case "pending": return "Enrichment pending"
        case "enriching": return "Enriching…"
        case "failed": return "Enrichment failed"
        default: return "No candidates"
        }
    }

    private func emptyMessage(for job: EnrichJob) -> String {
        switch job.status {
        case "pending": return "This job hasn't started enrichment yet — check back soon."
        case "enriching": return "Still searching providers for release candidates."
        case "failed": return job.error?.nonEmpty ?? "This job failed and produced no candidates."
        default: return "This job finished without finding any release candidates."
        }
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

struct ReleaseCandidateCard: View {
    let release: PendingRelease
    let busy: Bool
    let onConfirm: () -> Void
    let onDiscard: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Artwork(raw: release.artworkUrl, cornerRadius: 10)
                    .frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 3) {
                    Text(release.album?.nonEmpty ?? release.title?.nonEmpty ?? "Untitled release")
                        .font(.body.weight(.semibold)).foregroundStyle(Brand.text).lineLimit(2)
                    Text(release.artist?.nonEmpty ?? "—").font(.subheadline).foregroundStyle(Brand.muted).lineLimit(1)
                    HStack(spacing: 6) {
                        if let src = release.source?.nonEmpty { Badge(text: src, color: Brand.teal) }
                        MediaFormatBadge(raw: release.releaseFormat)
                        if let year = release.releaseDate?.prefix(4), !year.isEmpty {
                            Text(String(year)).font(.caption2).foregroundStyle(Brand.muted)
                        }
                    }
                }
                Spacer(minLength: 0)
            }

            if let list = release.tracklist, !list.isEmpty {
                Divider().overlay(Brand.border)
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(list.prefix(6)) { entry in
                        TracklistEntryRow(entry: entry)
                    }
                    if list.count > 6 {
                        Text("+ \(list.count - 6) more").font(.caption2).foregroundStyle(Brand.muted)
                    }
                }
            }

            HStack(spacing: 10) {
                Button(action: onConfirm) {
                    HStack { if busy { ProgressView().controlSize(.mini) }; Label("Confirm", systemImage: "checkmark.seal.fill") }
                        .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(Brand.gold).disabled(busy)

                Button(action: onDiscard) {
                    Label("Discard", systemImage: "trash").font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered).tint(Brand.muted).disabled(busy)
            }
        }
        .padding(16)
        .grooveCard(elevated: true)
    }
}
