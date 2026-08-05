import SwiftUI

/// Presented as a `.sheet()` from the mini-bar or Home — the model is app-owned
/// (started/stopped alongside the tab bar in `MainTabView`) so playback keeps
/// polling for the mini-bar even while this sheet is dismissed.
struct NowPlayingView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(NowPlayingModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var showInfo = false

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Now Playing")
                .navigationBarTitleDisplayMode(.inline)
                .grooveScreenBackground()
                .toolbar {
                    if let pb = model.status?.playback, pb.active {
                        ToolbarItem(placement: .topBarLeading) {
                            Button {
                                showInfo = true
                            } label: {
                                Image(systemName: "info.circle")
                                    .foregroundStyle(Brand.muted)
                            }
                            .accessibilityLabel("Recognition info")
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(Brand.muted)
                        }
                        .accessibilityLabel("Close")
                    }
                }
                .sheet(isPresented: $showInfo) {
                    if let pb = model.status?.playback {
                        RecognitionInfoSheet(playback: pb)
                    }
                }
        }
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private var content: some View {
        if !model.hasLoadedOnce {
            LoadingView(label: "Connecting…")
        } else if let pb = model.status?.playback, pb.active {
            playing(pb)
        } else {
            idle
        }
    }

    private func playing(_ pb: Playback) -> some View {
        ScrollView {
            VStack(spacing: 18) {
                Artwork(raw: pb.artworkUrl, cornerRadius: 20, label: artworkLabel(pb))
                    .frame(maxWidth: 300, maxHeight: 300)
                    .aspectRatio(1, contentMode: .fit)
                    .shadow(color: .black.opacity(0.5), radius: 24, y: 12)
                    .padding(.top, 4)

                VStack(spacing: 6) {
                    Text(pb.title?.nonEmpty ?? "Unknown title")
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Brand.text)
                    Text(pb.artist?.nonEmpty ?? "Unknown artist")
                        .font(.title3)
                        .foregroundStyle(Brand.teal)
                        .multilineTextAlignment(.center)
                    if let album = pb.album?.nonEmpty {
                        Text(album)
                            .font(.subheadline)
                            .foregroundStyle(Brand.muted)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal)

                HStack(spacing: 8) {
                    MediaFormatBadge(raw: pb.mediaFormat, labeled: true)
                    if let position = Format.trackPosition(pb.trackPosition) {
                        Badge(text: position, color: Brand.muted)
                    }
                }

                progress(pb)
            }
            .padding()
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .refreshable { await model.refresh(CatalogService(settings: settings)) }
        .safeAreaInset(edge: .bottom) {
            if let trackId = pb.trackId, trackId > 0 {
                NavigationLink {
                    TrackDetailView(trackId: trackId)
                } label: {
                    Label("Open in Library", systemImage: "arrow.up.forward.square")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(Brand.accent)
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 4)
                .frame(maxWidth: .infinity)
                .background(.ultraThinMaterial)
            }
        }
    }

    private func artworkLabel(_ pb: Playback) -> String {
        [pb.title?.nonEmpty, pb.artist?.nonEmpty].compactMap { $0 }.joined(separator: " by ")
    }

    private func progress(_ pb: Playback) -> some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let pos = model.interpolatedPositionMs(at: context.date)
            let dur = pb.durationMs ?? 0
            VStack(spacing: 6) {
                ProgressView(value: fraction(pos: pos, dur: dur))
                    .tint(Brand.teal)
                HStack {
                    Text(Format.duration(pos))
                    Spacer()
                    Text(dur > 0 ? Format.duration(dur) : "—")
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(Brand.muted)
            }
            .padding(.horizontal)
        }
    }

    private func fraction(pos: Int64?, dur: Int64) -> Double {
        guard let pos, dur > 0 else { return 0 }
        return min(1, max(0, Double(pos) / Double(dur)))
    }

    private var idle: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle().fill(Brand.card).frame(width: 120, height: 120)
                Image(systemName: "opticaldisc")
                    .font(.system(size: 52, weight: .light))
                    .foregroundStyle(Brand.muted)
            }
            Text("Nothing playing")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Brand.text)
            Text("Drop the needle — recognitions will appear here live.")
                .font(.subheadline)
                .foregroundStyle(Brand.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            if let err = model.errorMessage {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(Brand.err)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
