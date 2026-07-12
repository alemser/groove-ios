import SwiftUI
import Observation

@MainActor
@Observable
final class TrackDetailModel {
    var profile: TrackProfile?
    var phase: Phase = .loading
    var actionError: String?

    enum Phase: Equatable { case loading, loaded, error(String) }

    let trackId: Int64
    private var settings: AppSettings?

    init(trackId: Int64) { self.trackId = trackId }

    var track: Track? { profile?.track }

    func configure(_ settings: AppSettings) {
        if self.settings == nil {
            self.settings = settings
            Task { await load() }
        }
    }

    func load() async {
        guard let settings else { return }
        if profile == nil { phase = .loading }
        do {
            profile = try await CatalogService(settings: settings).trackProfile(id: trackId)
            phase = .loaded
        } catch {
            if profile == nil { phase = .error((error as? APIError)?.localizedDescription ?? error.localizedDescription) }
        }
    }

    func save(_ patch: TrackDisplayPatch) async -> Bool {
        guard let settings else { return false }
        do {
            let updated = try await CatalogService(settings: settings).patchTrackDisplay(id: trackId, patch: patch)
            if var profile { profile.track = updated; self.profile = profile }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            return true
        } catch {
            actionError = (error as? APIError)?.localizedDescription ?? error.localizedDescription
            return false
        }
    }

    func resetOverrides() async {
        _ = await save(TrackDisplayPatch(reset: true))
    }

    func delete() async -> Bool {
        guard let settings else { return false }
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
