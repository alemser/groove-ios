import SwiftUI
import Observation

/// One line of "what's playing" — the mini-bar and Home show this, for a
/// stream and a record alike.
struct NowPlayingSummary {
    var artworkUrl: String?
    var title: String
    var subtitle: String
    var isRecognizing: Bool
}

@MainActor
@Observable
final class NowPlayingModel {
    var status: CatalogStatus?
    var errorMessage: String?
    var hasLoadedOnce = false

    /// Wall-clock instant the current position (`status.playback.positionMs`
    /// or `status.streaming.positionMs`) was captured, so the UI can advance
    /// the progress bar smoothly between polls.
    private(set) var positionAnchoredAt = Date()

    /// Wall-clock instant `playback.active` was last true. Track transitions
    /// routinely have a real gap — the previous segment closes and the next
    /// isn't identified yet — where `active` genuinely reads false for a few
    /// seconds even though the listener never stopped. Without this, every
    /// transition flashed the full "Nothing playing" empty state.
    private(set) var lastActiveAt: Date?
    private let transitionGraceInterval: TimeInterval = 25

    private var poller: Poller?

    /// Set when answering the edition question failed, so the card can say so
    /// beside the buttons rather than failing silently.
    var editionErrorMessage: String?

    /// The open "which pressing is this?" question, if any (groove-identity#38).
    var editionQuestion: EditionQuestion? { status?.editionQuestion }

    /// What AirPlay or Bluetooth is playing. groove-display ranks a stream
    /// above the record, and so does every screen here.
    var streaming: StreamingPlayback? { status?.streaming }

    /// True when playback just went inactive but was active moments ago —
    /// "probably between tracks," not "nothing has played all session."
    func isLikelyTransitioning(at now: Date = Date()) -> Bool {
        guard status?.playback.active != true, let lastActiveAt else { return false }
        return now.timeIntervalSince(lastActiveAt) <= transitionGraceInterval
    }

    /// The stream, else the record (or one being recognised between
    /// tracks), else nil: nothing is playing.
    var summary: NowPlayingSummary? {
        if let s = streaming {
            return NowPlayingSummary(
                artworkUrl: s.artworkUrl,
                title: s.title?.nonEmpty ?? s.sourceLabel,
                subtitle: s.artist?.nonEmpty ?? s.sourceLabel,
                isRecognizing: false
            )
        }
        guard let pb = status?.playback, pb.active || isLikelyTransitioning() else { return nil }
        let recognizing = pb.isRecognizing || isLikelyTransitioning()
        return NowPlayingSummary(
            artworkUrl: pb.artworkUrl,
            title: pb.title?.nonEmpty ?? (recognizing ? "Recognizing…" : "Now Playing"),
            subtitle: pb.artist?.nonEmpty ?? (recognizing ? "Listening…" : "Unknown artist"),
            isRecognizing: recognizing
        )
    }

    func start(_ settings: AppSettings) {
        guard poller == nil else { return }
        let service = CatalogService(settings: settings)
        let p = Poller(interval: .seconds(2)) { [weak self] in await self?.refresh(service) }
        poller = p
        p.start()
    }

    func stop() {
        poller?.stop()
        poller = nil
    }

    func refresh(_ service: CatalogService) async {
        do {
            let next = try await service.status()
            status = next
            positionAnchoredAt = Date()
            if next.playback.active { lastActiveAt = Date() }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedForDisplay
        }
        hasLoadedOnce = true
    }

    /// Answers the edition question. The session moves to that edition's
    /// tracklist and the choice is remembered for the album; the next poll
    /// clears the card because the question is gone server-side.
    func chooseEdition(_ option: EditionOption, settings: AppSettings) async {
        let service = CatalogService(settings: settings)
        do {
            try await service.chooseAlbumProgrammeEdition(source: option.source, releaseId: option.releaseId)
            editionErrorMessage = nil
            await refresh(service)
        } catch {
            editionErrorMessage = error.localizedForDisplay
        }
    }

    func dismissEditionQuestion(settings: AppSettings) async {
        let service = CatalogService(settings: settings)
        do {
            try await service.dismissAlbumProgrammeEditionQuestion()
            editionErrorMessage = nil
            await refresh(service)
        } catch {
            editionErrorMessage = error.localizedForDisplay
        }
    }

    /// Interpolated position in ms at `now` — of the stream when one plays,
    /// else of the record — clamped to the track length.
    func interpolatedPositionMs(at now: Date) -> Int64? {
        let base: Int64?
        let duration: Int64?
        if let s = streaming {
            (base, duration) = (s.positionMs, s.durationMs)
        } else {
            guard let pb = status?.playback, pb.active else { return status?.playback.positionMs }
            (base, duration) = (pb.positionMs, pb.durationMs)
        }
        guard let base else { return nil }
        let value = base + max(0, Int64(now.timeIntervalSince(positionAnchoredAt) * 1000))
        if let duration, duration > 0 { return min(value, duration) }
        return value
    }
}
