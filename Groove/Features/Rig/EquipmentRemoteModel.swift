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

    enum Phase: Equatable { case loading, loaded, error(String) }

    private var settings: AppSettings?

    /// The amplifier is registered as a target like any other, but it already
    /// has its own screen — listing it again here would just be confusing.
    var otherEquipment: [RigEquipmentItem] { equipment.filter { $0.id != "amplifier" } }

    func configure(_ settings: AppSettings) {
        if self.settings == nil {
            self.settings = settings
            Task { await load() }
        }
    }

    func load() async {
        guard let settings else { return }
        if equipment.isEmpty { phase = .loading }
        do {
            let service = CatalogService(settings: settings)
            async let eq = service.rigEquipment()
            async let snap = service.rigStatus()
            equipment = try await eq
            snapshot = try await snap
            phase = .loaded
        } catch {
            if equipment.isEmpty {
                phase = .error((error as? APIError)?.localizedDescription ?? error.localizedDescription)
            }
        }
    }

    func isLearned(targetId: String, action: String) -> Bool {
        snapshot?.targets.first { $0.id == targetId }?.actions[action]?.learned ?? false
    }

    func fire(targetId: String, action: String) async {
        guard let settings, !isPerformingAction else { return }
        isPerformingAction = true
        defer { isPerformingAction = false }
        do {
            snapshot = try await CatalogService(settings: settings).rigAction(target: targetId, action: action)
            actionError = nil
        } catch {
            actionError = (error as? APIError)?.localizedDescription ?? error.localizedDescription
        }
    }

    func unlearn(targetId: String, action: String) async {
        guard let settings else { return }
        do {
            try await CatalogService(settings: settings).rigUnlearn(target: targetId, action: action)
            await load()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            actionError = (error as? APIError)?.localizedDescription ?? error.localizedDescription
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
            actionError = (error as? APIError)?.localizedDescription ?? error.localizedDescription
            return false
        }
    }

    func deleteEquipment(id: String) async {
        guard let settings else { return }
        do {
            try await CatalogService(settings: settings).rigDeleteEquipment(id: id)
            await load()
        } catch {
            actionError = (error as? APIError)?.localizedDescription ?? error.localizedDescription
        }
    }
}
