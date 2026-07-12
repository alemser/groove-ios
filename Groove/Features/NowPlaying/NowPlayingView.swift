import SwiftUI

struct NowPlayingView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = NowPlayingModel()

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Now Playing")
                .grooveScreenBackground()
        }
        .task { model.start(settings) }
        .onDisappear { model.stop() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.start(settings) } else { model.stop() }
        }
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
            VStack(spacing: 24) {
                Artwork(raw: pb.artworkUrl, cornerRadius: 20)
                    .frame(maxWidth: 320)
                    .aspectRatio(1, contentMode: .fit)
                    .shadow(color: .black.opacity(0.5), radius: 24, y: 12)
                    .padding(.top, 12)

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

                progress(pb)

                HStack(spacing: 8) {
                    if let source = pb.source?.nonEmpty {
                        Badge(text: SourceStyle.label(for: source), color: SourceStyle.color(for: source), filled: true)
                    }
                    if let media = Format.mediaFormat(pb.mediaFormat) {
                        Badge(text: media, color: Brand.gold)
                    }
                    if let conf = Format.confidence(pb.confidence) {
                        Badge(text: conf, color: Brand.muted)
                    }
                }

                if let trackId = pb.trackId, trackId > 0 {
                    NavigationLink {
                        TrackDetailView(trackId: trackId)
                    } label: {
                        Label("Open in Library", systemImage: "arrow.up.forward.square")
                            .font(.subheadline.weight(.medium))
                    }
                    .buttonStyle(.bordered)
                    .tint(Brand.accent)
                }
            }
            .padding()
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .refreshable { await model.refresh(CatalogService(settings: settings)) }
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
