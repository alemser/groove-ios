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

    func activate(profileId: String) async {
        guard let settings else { return }
        do {
            _ = try await CatalogService(settings: settings).rigActivateProfile(id: profileId)
            await load()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            actionError = (error as? APIError)?.localizedDescription ?? error.localizedDescription
        }
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
