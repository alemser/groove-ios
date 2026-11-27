import SwiftUI
import Observation

@MainActor
@Observable
final class AmplifierConfigModel {
    var config: RigAmplifierConfig?
    var profiles: [RigStoredAmplifierProfile] = []
    var activeProfileId: String?
    var phase: Phase = .loading
    var isSaving = false
    /// Whether the amplifier's selected input may inform which medium is
    /// playing. Loaded and saved separately from `config` — see `RigFormatHint`.
    var useAmplifierInputForFormat = true

    enum Phase: Equatable { case loading, loaded, error(String) }

    /// An amplifier is set up. groove-rig reports an empty active profile
    /// until the first one is activated, which is what registers the
    /// amplifier; a new installation has none. Profiles that failed to load
    /// (nil) leave the screen as it was.
    var hasAmplifier: Bool { activeProfileId != "" }

    private var settings: AppSettings?
    private var messages: MessageCenter?

    func configure(_ settings: AppSettings, messages: MessageCenter) {
        if self.settings == nil {
            self.settings = settings
            self.messages = messages
            Task { await load() }
        }
    }

    /// A change to the amplifier setup, then a reload; true when it went through.
    @discardableResult
    private func mutate(_ action: @escaping (CatalogService) async throws -> Void) async -> Bool {
        guard let settings, let messages else { return false }
        return await messages.attempt {
            try await action(CatalogService(settings: settings))
            await self.load()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } != nil
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
        // show.
        if let profResp = try? await profs {
            profiles = profResp.profiles
            activeProfileId = profResp.activeProfileId
        }
        useAmplifierInputForFormat = (try? await hint)?.useAmplifierInput ?? true
        phase = .loaded
    }

    @discardableResult
    func save(_ patch: RigAmplifierConfig, useAmplifierInputForFormat: Bool) async -> Bool {
        guard let settings, let messages else { return false }
        isSaving = true
        defer { isSaving = false }
        return await messages.attempt {
            let service = CatalogService(settings: settings)
            self.config = try await service.rigPatchAmplifier(patch)
            let hint = try await service.rigSetFormatHint(useAmplifierInput: useAmplifierInputForFormat)
            self.useAmplifierInputForFormat = hint.useAmplifierInput
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } != nil
    }

    /// Switches amplifier. Never blocked: groove-rig saves edits into the
    /// active profile as they're made (a built-in's override, or the custom
    /// profile), so switching away and back restores them.
    func activate(profileId: String) async {
        await mutate { try await $0.rigActivateProfile(id: profileId) }
    }

    /// "No Amplifier": groove-rig keeps the amplifier's settings, wiring and
    /// learned codes in its profile, so choosing it again restores them.
    func removeAmplifier() async {
        await mutate { try await $0.rigRemoveAmplifier() }
    }

    /// Copies `source` under a new name, with its learned IR codes and
    /// equipment wiring. Returns the new profile's id on success.
    func duplicateProfile(_ source: RigStoredAmplifierProfile, name: String) async -> String? {
        let base = Self.slug(name)
        var id = base
        var n = 2
        while profiles.contains(where: { $0.id == id }) {
            id = "\(base)_\(n)"
            n += 1
        }
        let request = RigProfileDuplicateRequest(id: id, name: name, config: source.config, copyCodesFrom: source.id)
        let done = await mutate { _ = try await $0.rigDuplicateProfile(request) }
        return done ? id : nil
    }

    func resetProfile(id: String) async {
        await mutate { try await $0.rigResetProfile(id: id) }
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
        await mutate { try await $0.rigDeleteProfile(id: id) }
    }

    func exportProfile(id: String) async -> RigProfileExportDoc? {
        guard let settings, let messages else { return nil }
        return await messages.attempt { try await CatalogService(settings: settings).rigExportProfile(id: id) }
    }

    @discardableResult
    func importProfile(_ doc: RigProfileExportDoc) async -> Bool {
        await mutate { _ = try await $0.rigImportProfile(doc) }
    }
}
