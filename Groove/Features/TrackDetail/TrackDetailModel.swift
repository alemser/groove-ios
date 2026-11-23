import SwiftUI
import Observation

@MainActor
@Observable
final class TrackDetailModel {
    var profile: TrackProfile?
    var phase: Phase = .loading

    enum Phase: Equatable { case loading, loaded, error(String) }

    let trackId: Int64
    private var settings: AppSettings?
    private var messages: MessageCenter?

    init(trackId: Int64) { self.trackId = trackId }

    var track: Track? { profile?.track }

    func configure(_ settings: AppSettings, messages: MessageCenter) {
        if self.settings == nil {
            self.settings = settings
            self.messages = messages
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
            if profile == nil { phase = .error(error.localizedForDisplay) }
        }
    }

    func save(_ patch: TrackDisplayPatch) async -> Bool {
        await attempt { service in
            let updated = try await service.patchTrackDisplay(id: self.trackId, patch: patch)
            if var profile = self.profile { profile.track = updated; self.profile = profile }
        }
    }

    func resetOverrides() async {
        _ = await save(TrackDisplayPatch(reset: true))
    }

    func delete() async -> Bool {
        await attempt { try await $0.deleteTrack(id: self.trackId) }
    }

    /// Rejects a wrongly-recognized play with no replacement — just removes
    /// the listening record. Reloads so the track's recent-plays list and
    /// counts stay in sync (this track itself may have had only this one
    /// play, in which case it now shows zero).
    @discardableResult
    func rejectPlay(epoch: UInt64) async -> Bool {
        await attempt { service in
            try await service.deletePlay(epoch: epoch)
            await self.load()
        }
    }

    /// A write the person asked for, confirmed with a haptic; a failure goes to the message center.
    private func attempt(_ action: @escaping (CatalogService) async throws -> Void) async -> Bool {
        guard let settings, let messages else { return false }
        return await messages.attempt {
            try await action(CatalogService(settings: settings))
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } != nil
    }
}
