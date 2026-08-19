import SwiftUI
import Observation

@MainActor
@Observable
final class AmplifierConfigModel {
    var config: RigAmplifierConfig?
    var profiles: [RigStoredAmplifierProfile] = []
    var activeProfileId: String?
    var phase: Phase = .loading
    var actionError: String?
    var isSaving = false
    /// Set when the server refuses `activate` (409) because the live config
    /// has unsaved local edits on top of the currently active profile —
    /// switching would silently discard them. The view shows a confirm
    /// alert; confirming retries with `force: true`.
    var pendingForceActivate: (profileId: String, message: String)?
    /// Set right after a forced activate that had to back up diverged
    /// local edits — names the new profile they landed in, so the view can
    /// tell the user where their previous setup went instead of leaving
    /// them to wonder whether "Discard and Activate" really discarded it.
    var lastBackupProfileId: String?

    enum Phase: Equatable { case loading, loaded, error(String) }

    private var settings: AppSettings?

    func configure(_ settings: AppSettings) {
        if self.settings == nil {
            self.settings = settings
            Task { await load() }
        }
    }

    func load() async {
        guard let settings else { return }
        if config == nil { phase = .loading }
        do {
            let service = CatalogService(settings: settings)
            async let cfg = service.rigAmplifierConfig()
            async let profs = service.rigAmplifierProfiles()
            config = try await cfg
            let profResp = try await profs
            profiles = profResp.profiles
            activeProfileId = profResp.activeProfileId
            phase = .loaded
        } catch {
            if config == nil {
                phase = .error((error as? APIError)?.localizedDescription ?? error.localizedDescription)
            }
        }
    }

    @discardableResult
    func save(_ patch: RigAmplifierConfig) async -> Bool {
        guard let settings else { return false }
        isSaving = true
        defer { isSaving = false }
        do {
            config = try await CatalogService(settings: settings).rigPatchAmplifier(patch)
            actionError = nil
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            return true
        } catch {
            actionError = (error as? APIError)?.localizedDescription ?? error.localizedDescription
            return false
        }
    }

    func activate(profileId: String, force: Bool = false) async {
        guard let settings else { return }
        do {
            let res = try await CatalogService(settings: settings).rigActivateProfile(id: profileId, force: force)
            lastBackupProfileId = res.backupProfileId
            await load()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch let error as APIError {
            if case let .http(status, body) = error, status == 409 {
                pendingForceActivate = (profileId, Self.extractServerMessage(from: body) ?? error.localizedDescription)
            } else {
                actionError = error.localizedDescription
            }
        } catch {
            actionError = error.localizedDescription
        }
    }

    /// Pulls `{"error": "..."}` out of a raw HTTP error body, matching the
    /// shape groove-rig's `writeError` sends — falls back to nil (caller
    /// shows the generic `APIError.http` description instead) for anything
    /// that isn't that shape.
    private static func extractServerMessage(from body: String) -> String? {
        guard let data = body.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return obj["error"] as? String
    }

    @discardableResult
    func saveAsNewProfile(id: String, name: String) async -> Bool {
        guard let settings, let config else { return false }
        do {
            _ = try await CatalogService(settings: settings).rigSaveProfile(
                RigStoredAmplifierProfile(id: id, name: name, origin: "custom", config: config)
            )
            await load()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            return true
        } catch {
            actionError = (error as? APIError)?.localizedDescription ?? error.localizedDescription
            return false
        }
    }

    func deleteProfile(id: String) async {
        guard let settings else { return }
        do {
            try await CatalogService(settings: settings).rigDeleteProfile(id: id)
            await load()
        } catch {
            actionError = (error as? APIError)?.localizedDescription ?? error.localizedDescription
        }
    }

    func exportProfile(id: String) async -> RigProfileExportDoc? {
        guard let settings else { return nil }
        do {
            return try await CatalogService(settings: settings).rigExportProfile(id: id)
        } catch {
            actionError = (error as? APIError)?.localizedDescription ?? error.localizedDescription
            return nil
        }
    }

    @discardableResult
    func importProfile(_ doc: RigProfileExportDoc) async -> Bool {
        guard let settings else { return false }
        do {
            _ = try await CatalogService(settings: settings).rigImportProfile(doc)
            await load()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            return true
        } catch {
            actionError = (error as? APIError)?.localizedDescription ?? error.localizedDescription
            return false
        }
    }
}
