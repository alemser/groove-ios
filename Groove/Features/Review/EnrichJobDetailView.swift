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
    private var settings: AppSettings?

    init(jobId: Int64) { self.jobId = jobId }

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
}

struct EnrichJobDetailView: View {
    let job: EnrichJob
    @Environment(AppSettings.self) private var settings
    @State private var model: EnrichJobDetailModel

    init(job: EnrichJob) {
        self.job = job
        _model = State(initialValue: EnrichJobDetailModel(jobId: job.id))
    }

    var body: some View {
        content
            .grooveScreenBackground()
            .navigationTitle("Release Candidates")
            .navigationBarTitleDisplayMode(.inline)
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
                    let releases = model.detail?.releases ?? []
                    if releases.isEmpty {
                        EmptyStateView(icon: "tray", title: "No candidates", message: "This job has no pending release candidates.")
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
        return VStack(alignment: .leading, spacing: 6) {
            Text(j.title?.nonEmpty ?? "Job #\(j.id)").font(.title3.bold()).foregroundStyle(Brand.text)
            Text(j.artist?.nonEmpty ?? "—").font(.subheadline).foregroundStyle(Brand.teal)
            HStack { EnrichStatusBadge(status: j.status); if let isrc = j.isrc?.nonEmpty { Badge(text: isrc, color: Brand.muted) } }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .grooveCard()
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
                        if let media = Format.mediaFormat(release.releaseFormat) { Badge(text: media, color: Brand.gold) }
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
                        HStack {
                            Text(entry.position ?? "\(entry.ordinal)")
                                .font(.caption.monospacedDigit()).foregroundStyle(Brand.muted).frame(width: 28, alignment: .leading)
                            Text(entry.title?.nonEmpty ?? "—").font(.caption).foregroundStyle(Brand.text).lineLimit(1)
                            Spacer()
                            Text(Format.duration(entry.durationMs)).font(.caption.monospacedDigit()).foregroundStyle(Brand.muted)
                        }
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
