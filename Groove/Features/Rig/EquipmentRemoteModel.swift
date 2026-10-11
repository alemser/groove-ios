import SwiftUI
import Observation

@MainActor
@Observable
final class EquipmentRemoteModel {
    var equipment: [RigEquipmentItem] = []
    var snapshot: RigSnapshot?
    var phase: Phase = .loading
    var actionError: String?
    var isPerformingAction = false
    /// Well-known buttons and equipment templates from groove-rig — the
    /// server owns "which buttons does this kind of device have", not the
    /// app. Supplementary: empty on an older server, and nothing breaks.
    var vocabulary: [RigActionDef] = []
    var templates: [RigEquipmentTemplate] = []
    /// Built-in makes/models that ship IR codes. Supplementary like
    /// templates: empty on a server without GET /rig/equipment/models.
    var builtInModels: [RigEquipmentModel] = []

    enum Phase: Equatable { case loading, loaded, error(String) }

    static let powerKeys: Set<String> = ["power_toggle", "power_on", "power_off"]

    func icon(for action: String) -> String? {
        if Self.powerKeys.contains(action) { return "power" }
        return vocabulary.first { $0.id == action }?.icon
    }

    /// Built-in models of one kind (template id), for a Model picker.
    func builtInModels(ofKind templateId: String?) -> [RigEquipmentModel] {
        builtInModels.filter { $0.templateId == templateId }
    }

    /// The template describing `item` — its own, or (for equipment added
    /// before templates existed) a guess from its format/role.
    func template(for item: RigEquipmentItem) -> RigEquipmentTemplate? {
        if item.id == "amplifier" { return templates.first { $0.id == "amplifier" } }
        if let id = item.templateId, let t = templates.first(where: { $0.id == id }) { return t }
        let guess: String?
        switch item.physicalFormat {
        case "cd": guess = "cd_player"
        case "tape": guess = "cassette_deck"
        case "vinyl": guess = "turntable"
        default: guess = item.role == "streaming" ? "streamer" : nil
        }
        return guess.flatMap { g in templates.first { $0.id == g } }
    }

    /// The template's buttons `item` doesn't have yet, in the template's
    /// order — standard and optional ones alike. What Add Button suggests
    /// ("Common on … remotes") and its "Walk Me Through All". Buttons its
    /// built-in model ships codes for are left out: they need no teaching
    /// (`missingShippedButtons`).
    func missingTemplateButtons(for item: RigEquipmentItem) -> [String] {
        guard let t = template(for: item) else { return [] }
        let shipped = Set(missingShippedButtons(for: item))
        return missing(t.actions + t.optionalActions, for: item).filter { !shipped.contains($0) }
    }

    /// The built-in model `item` was registered as, if any.
    func builtInModel(for item: RigEquipmentItem) -> RigEquipmentModel? {
        builtInModels.first { $0.id == item.modelId }
    }

    /// Buttons `item`'s built-in model ships codes for that aren't on it
    /// yet — only the standard ones are registered on create, so a full
    /// remote's number keys, Program, Dimmer… wait here, one tap from working.
    func missingShippedButtons(for item: RigEquipmentItem) -> [String] {
        guard let m = builtInModel(for: item) else { return [] }
        return missing(m.actions, for: item)
    }

    /// Adds buttons whose codes ship with the model — no learning.
    func addShippedButtons(targetId: String, actions: [String]) async {
        guard let settings else { return }
        do {
            let service = CatalogService(settings: settings)
            for a in actions { try await service.rigAddEquipmentAction(target: targetId, action: a) }
            await load()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            actionError = error.localizedForDisplay
            await load()
        }
    }

    /// Only the template's *standard* buttons that are still missing — the
    /// ones a remote of this kind is expected to have. Optional extras
    /// (Mute, Display, number keys…) aren't "unfinished work", so they
    /// never drive the "Teach the Remote" prompt; they stay suggestions.
    /// `extra`: buttons standard for this particular device beyond its
    /// template — the Bass/Treble keys of an amplifier whose profile has
    /// remote tone control.
    func missingStandardButtons(for item: RigEquipmentItem, extra: [String] = []) -> [String] {
        let standard = (template(for: item)?.actions ?? []) + extra
        return missing(standard, for: item)
    }

    private func missing(_ actions: [String], for item: RigEquipmentItem) -> [String] {
        let have = item.actions ?? []
        let hasPower = have.contains { Self.powerKeys.contains($0) }
        return actions.filter { a in
            !have.contains(a) && !(hasPower && Self.powerKeys.contains(a))
        }
    }

    func vocabularyLabel(_ action: String) -> String {
        if Self.powerKeys.contains(action) { return "Power" }
        return vocabulary.first { $0.id == action }?.label ?? action.replacingOccurrences(of: "_", with: " ").capitalized
    }

    func renameButton(targetId: String, action: String, label: String) async {
        guard let settings else { return }
        do {
            try await CatalogService(settings: settings).rigRenameEquipmentAction(target: targetId, action: action, label: label)
            await load()
        } catch {
            actionError = error.localizedForDisplay
        }
    }

    /// Removes the button and its learned code (power: every power key).
    func removeButton(targetId: String, actions: [String]) async {
        guard let settings else { return }
        do {
            let service = CatalogService(settings: settings)
            for a in actions { try await service.rigRemoveEquipmentAction(target: targetId, action: a) }
            await load()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            actionError = error.localizedForDisplay
        }
    }

    private var settings: AppSettings?

    /// The amplifier is registered as a target like any other, but it already
    /// has its own screen — listing it again here would just be confusing.
    var otherEquipment: [RigEquipmentItem] { equipment.filter { $0.id != "amplifier" } }

    /// The amplifier's own entry — same target, same command-teaching flow,
    /// surfaced from Amplifier → Configuration instead of the Equipment list.
    var amplifierEquipment: RigEquipmentItem? { equipment.first { $0.id == "amplifier" } }

    func configure(_ settings: AppSettings) {
        if self.settings == nil {
            self.settings = settings
            Task { await load() }
        }
    }

    func load() async {
        guard let settings else { return }
        if equipment.isEmpty { phase = .loading }
        let service = CatalogService(settings: settings)
        async let eq = service.rigEquipment()
        async let snap = service.rigStatus()
        async let vocab = service.rigActionVocabulary()
        async let tpls = service.rigEquipmentTemplates()
        async let models = service.rigEquipmentModels()
        do {
            equipment = try await eq
        } catch {
            if equipment.isEmpty {
                phase = .error(error.localizedForDisplay)
            }
            return
        }
        // The learned-state snapshot is supplementary — isLearned() already
        // degrades to false without it — so a failure here shouldn't blank a
        // screen that already has a real equipment list to show.
        snapshot = (try? await snap) ?? snapshot
        // Also supplementary — degrade to what we had (CLAUDE.md async-let rule).
        vocabulary = (try? await vocab)?.items ?? vocabulary
        templates = (try? await tpls) ?? templates
        builtInModels = (try? await models) ?? builtInModels
        phase = .loaded
    }

    func isLearned(targetId: String, action: String) -> Bool {
        snapshot?.targets.first { $0.id == targetId }?.actions[action]?.learned ?? false
    }

    /// Working only through the amplifier profile's shipped code.
    func isBuiltin(targetId: String, action: String) -> Bool {
        snapshot?.targets.first { $0.id == targetId }?.actions[action]?.builtin ?? false
    }

    /// The amplifier profile ships a code for this button (local or not).
    func hasBuiltinCode(targetId: String, action: String) -> Bool {
        snapshot?.targets.first { $0.id == targetId }?.actions[action]?.builtinAvailable ?? false
    }

    func fire(targetId: String, action: String) async {
        guard let settings, !isPerformingAction else { return }
        isPerformingAction = true
        defer { isPerformingAction = false }
        do {
            snapshot = try await CatalogService(settings: settings).rigAction(target: targetId, action: action)
            actionError = nil
        } catch {
            actionError = error.localizedForDisplay
            // The tap was confirmed by a haptic before the request went out; a
            // failure has to be felt too, or the operator is left believing the
            // command reached the equipment.
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    func unlearn(targetId: String, action: String) async {
        guard let settings else { return }
        do {
            try await CatalogService(settings: settings).rigUnlearn(target: targetId, action: action)
            await load()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            actionError = error.localizedForDisplay
        }
    }

    @discardableResult
    func addEquipment(_ req: RigEquipmentSaveRequest) async -> Bool {
        guard let settings else { return false }
        do {
            _ = try await CatalogService(settings: settings).rigCreateEquipment(req)
            await load()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            return true
        } catch {
            actionError = error.localizedForDisplay
            return false
        }
    }

    func deleteEquipment(id: String) async {
        guard let settings else { return }
        do {
            try await CatalogService(settings: settings).rigDeleteEquipment(id: id)
            await load()
        } catch {
            actionError = error.localizedForDisplay
        }
    }

    /// Registers `action` into `targetId`'s actions list if it isn't there
    /// yet. Learning writes to the codebook regardless of the target's
    /// configured actions, but `GET /status` only reports "learned" for
    /// actions actually listed there — mirrors studio.html's
    /// `ensureActionRegistered`. Used for the amplifier's per-input
    /// `select_<id>` direct-mode actions, which (unlike the fixed transport
    /// actions on other equipment) aren't known ahead of time.
    func ensureActionRegistered(targetId: String, action: String) async {
        guard let item = equipment.first(where: { $0.id == targetId }) else { return }
        var actions = item.actions ?? []
        guard !actions.contains(action) else { return }
        actions.append(action)
        await updateEquipment(id: targetId, RigEquipmentPatchRequest(
            label: nil, backend: nil, actions: actions, role: nil, physicalFormat: nil, inputIds: nil, hasRemote: nil
        ))
    }

    @discardableResult
    func updateEquipment(id: String, _ patch: RigEquipmentPatchRequest) async -> Bool {
        guard let settings else { return false }
        do {
            _ = try await CatalogService(settings: settings).rigPatchEquipment(id: id, patch)
            await load()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            return true
        } catch {
            actionError = error.localizedForDisplay
            return false
        }
    }
}
