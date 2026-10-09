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
    /// Whether the amplifier's selected input may inform which medium is
    /// playing. Loaded and saved separately from `config` — see `RigFormatHint`.
    var useAmplifierInputForFormat = true

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
        let service = CatalogService(settings: settings)
        async let cfg = service.rigAmplifierConfig()
        async let profs = service.rigAmplifierProfiles()
        async let hint = service.rigFormatHint()
        do {
            config = try await cfg
        } catch {
            if config == nil {
                phase = .error(error.localizedForDisplay)
            }
            return
        }
        // Profiles and the format hint are supplementary — a failure fetching
        // either shouldn't blank a screen that already has a real config to
        // show. An older groove-rig has no format-hint route at all, so a 404
        // there must not block the rest of the screen either.
        if let profResp = try? await profs {
            profiles = profResp.profiles
            activeProfileId = profResp.activeProfileId
        }
        useAmplifierInputForFormat = (try? await hint)?.useAmplifierInput ?? true
        phase = .loaded
    }

    @discardableResult
    func save(_ patch: RigAmplifierConfig, useAmplifierInputForFormat: Bool) async -> Bool {
        guard let settings else { return false }
        isSaving = true
        defer { isSaving = false }
        do {
            let service = CatalogService(settings: settings)
            config = try await service.rigPatchAmplifier(patch)
            let hint = try await service.rigSetFormatHint(useAmplifierInput: useAmplifierInputForFormat)
            self.useAmplifierInputForFormat = hint.useAmplifierInput
            actionError = nil
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            return true
        } catch {
            actionError = error.localizedForDisplay
            return false
        }
    }

    /// Switches amplifier. Never blocked: groove-rig saves edits into the
    /// active profile as they're made (a built-in's override, or the custom
    /// profile), so switching away and back restores them.
    func activate(profileId: String) async {
        guard let settings else { return }
        do {
            try await CatalogService(settings: settings).rigActivateProfile(id: profileId)
            await load()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            actionError = error.localizedForDisplay
        }
    }

    /// Copies `source` under a new name, with its learned IR codes and
    /// equipment wiring. Returns the new profile's id on success.
    func duplicateProfile(_ source: RigStoredAmplifierProfile, name: String) async -> String? {
        guard let settings else { return nil }
        let base = Self.slug(name)
        var id = base
        var n = 2
        while profiles.contains(where: { $0.id == id }) {
            id = "\(base)_\(n)"
            n += 1
        }
        do {
            _ = try await CatalogService(settings: settings).rigDuplicateProfile(
                RigProfileDuplicateRequest(id: id, name: name, config: source.config, copyCodesFrom: source.id)
            )
            await load()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            return id
        } catch {
            actionError = error.localizedForDisplay
            return nil
        }
    }

    func resetProfile(id: String) async {
        guard let settings else { return }
        do {
            try await CatalogService(settings: settings).rigResetProfile(id: id)
            await load()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            actionError = error.localizedForDisplay
        }
    }

    /// Profile ids are internal (`^[a-z0-9][a-z0-9_-]*$` on the server).
    private static func slug(_ text: String) -> String {
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789")
        var out = ""
        for ch in text.lowercased() {
            if allowed.contains(ch) {
                out.append(ch)
            } else if !out.hasSuffix("_") {
                out.append("_")
            }
        }
        let trimmed = out.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return trimmed.isEmpty ? "profile" : trimmed
    }

    func deleteProfile(id: String) async {
        guard let settings else { return }
        do {
            try await CatalogService(settings: settings).rigDeleteProfile(id: id)
            await load()
        } catch {
            actionError = error.localizedForDisplay
        }
    }

    func exportProfile(id: String) async -> RigProfileExportDoc? {
        guard let settings else { return nil }
        do {
            return try await CatalogService(settings: settings).rigExportProfile(id: id)
        } catch {
            actionError = error.localizedForDisplay
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
            actionError = error.localizedForDisplay
            return false
        }
    }
}
