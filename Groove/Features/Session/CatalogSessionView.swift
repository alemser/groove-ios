import SwiftUI

/// Live dashboard for autonomous-mode listening sittings — the iOS counterpart
/// to the web studio's "Catalog session" page. Own-owned polling model (started/
/// stopped with this screen), presented from `HomeView` only while autonomous
/// mode is on, mirroring the web nav's autonomous-only visibility.
struct CatalogSessionView: View {
    @Environment(AppSettings.self) private var settings
    @State private var model = CatalogSessionModel()
    @State private var resolving: PendingAssociation?
    @State private var showEditRelease = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                currentPanel
                historyPanel
            }
            .padding()
        }
        .scrollContentBackground(.hidden)
        .grooveScreenBackground()
        .navigationTitle("Catalog Session")
        .navigationBarTitleDisplayMode(.inline)
        .task { model.configure(settings) }
        .onDisappear { model.stop() }
        .sheet(isPresented: $showEditRelease) {
            if let jobId = model.currentJobId, let draft = model.currentDraft {
                EditReleaseView(jobId: jobId, draft: draft)
            }
        }
        .sheet(item: $resolving) { item in
            ManualIdentifySheet(
                epoch: item.listenerEpoch,
                seedArtist: item.suggestedArtist,
                seedTitle: item.suggestedTitle,
                seedAlbum: item.suggestedAlbum
            ) {}
        }
    }

    // MARK: - Current

    @ViewBuilder
    private var currentPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel(text: "Current")

            if model.isIdle {
                Text("Nothing playing right now.")
                    .font(.subheadline)
                    .foregroundStyle(Brand.muted)
            } else {
                if let pb = model.lastPlayback {
                    currentHead(pb)
                }
                if model.isBetweenTracks {
                    Text("Between tracks — waiting for the next one…")
                        .font(.caption)
                        .foregroundStyle(Brand.muted)
                }
                if model.livePlayback?.active == true {
                    progress
                }
                if !model.tracklist.isEmpty {
                    tracklistList
                }
            }
        }
        .padding(16)
        .background(Brand.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Brand.border, lineWidth: 1))
    }

    private func currentHead(_ pb: Playback) -> some View {
        HStack(spacing: 14) {
            Artwork(raw: pb.artworkUrl, cornerRadius: 10)
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 3) {
                Text(pb.artist?.nonEmpty ?? "—")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Brand.text)
                    .lineLimit(1)
                Text(pb.album?.nonEmpty ?? "")
                    .font(.subheadline)
                    .foregroundStyle(Brand.muted)
                    .lineLimit(1)
                if model.currentJobId != nil {
                    Button("Edit release (artwork, metadata) →") { showEditRelease = true }
                        .font(.caption)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var progress: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let pos = model.interpolatedPositionMs(at: context.date)
            let dur = model.livePlayback?.durationMs ?? 0
            VStack(spacing: 4) {
                ProgressView(value: fraction(pos: pos, dur: dur))
                    .tint(Brand.teal)
                HStack {
                    Text(Format.duration(pos))
                    Spacer()
                    Text(dur > 0 ? Format.duration(dur) : "—")
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(Brand.muted)
            }
        }
    }

    private func fraction(pos: Int64?, dur: Int64) -> Double {
        guard let pos, dur > 0 else { return 0 }
        return min(1, max(0, Double(pos) / Double(dur)))
    }

    private var tracklistList: some View {
        let sorted = model.tracklist.sorted { $0.ordinal < $1.ordinal }
        return VStack(spacing: 0) {
            ForEach(Array(sorted.enumerated()), id: \.element.id) { index, entry in
                SessionTracklistRow(
                    entry: entry,
                    state: entry.ordinal == model.highlightOrdinal ? .now
                        : entry.ordinal <= model.doneCutoff ? .done : .notYet
                )
                if index != sorted.count - 1 {
                    Divider().overlay(Brand.border)
                }
            }
        }
        .padding(.top, 4)
    }

    // MARK: - History

    private var historyPanel: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(text: "Confirmed this sitting")
                if model.confirmedHistory.isEmpty {
                    Text("Nothing confirmed yet this sitting.")
                        .font(.caption)
                        .foregroundStyle(Brand.muted)
                } else {
                    ForEach(model.confirmedHistory) { entry in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Image(systemName: "checkmark").font(.caption2).foregroundStyle(Brand.teal)
                                Text("\(entry.artist) — \(entry.title)")
                                    .font(.subheadline)
                                    .foregroundStyle(Brand.text)
                                    .lineLimit(1)
                            }
                            if !entry.album.isEmpty {
                                Text(entry.album).font(.caption).foregroundStyle(Brand.muted)
                            }
                        }
                        .padding(.vertical, 6)
                        if entry.id != model.confirmedHistory.last?.id {
                            Divider().overlay(Brand.border)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(text: "Pending")
                if model.pending.isEmpty {
                    Text("Nothing waiting on confirmation.")
                        .font(.caption)
                        .foregroundStyle(Brand.muted)
                } else {
                    ForEach(model.pending) { item in
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.suggestedTitle?.nonEmpty ?? "Unidentified play")
                                    .font(.subheadline)
                                    .foregroundStyle(Brand.text)
                                    .lineLimit(1)
                                Text(Format.relative(item.startedAt))
                                    .font(.caption2)
                                    .foregroundStyle(Brand.muted)
                            }
                            Spacer(minLength: 8)
                            Button("Resolve →") { resolving = item }
                                .font(.caption.weight(.semibold))
                        }
                        .padding(.vertical, 6)
                        if item.id != model.pending.last?.id {
                            Divider().overlay(Brand.border)
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(Brand.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Brand.border, lineWidth: 1))
    }
}

/// Three-state tracklist row (now / done / not-yet) — the session screen's
/// distinctive visual, kept local rather than folded into the shared
/// `TracklistEntryRow` (which only knows `isPlaying` vs not).
private struct SessionTracklistRow: View {
    enum RowState { case now, done, notYet }

    let entry: TracklistEntry
    let state: RowState

    var body: some View {
        HStack(spacing: 10) {
            Text(entry.position ?? "\(entry.ordinal)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(state == .now ? Brand.teal : Brand.muted)
                .frame(width: 32, alignment: .leading)
            Text(entry.title?.nonEmpty ?? "(untitled)")
                .font(.subheadline.weight(state == .now ? .semibold : .regular))
                .foregroundStyle(state == .now ? Brand.teal : Brand.text)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(Format.duration(entry.durationMs))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(Brand.muted)
            Group {
                if state == .now {
                    Circle().fill(Brand.teal).frame(width: 6, height: 6)
                } else if state == .done {
                    Image(systemName: "checkmark").font(.caption2).foregroundStyle(Brand.teal)
                }
            }
            .frame(width: 14)
        }
        .padding(.vertical, 8)
        .opacity(state == .notYet ? 0.55 : 1)
    }
}
