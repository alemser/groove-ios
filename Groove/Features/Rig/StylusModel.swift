import SwiftUI
import Observation

@MainActor
@Observable
final class StylusModel {
    var state: StylusState?
    var catalog: [StylusCatalogItem] = []
    var phase: Phase = .loading
    var actionError: String?

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
        if state == nil { phase = .loading }
        do {
            let service = CatalogService(settings: settings)
            async let stateTask = service.stylusState()
            async let catalogTask = service.stylusCatalog()
            state = try await stateTask
            catalog = try await catalogTask
            phase = .loaded
        } catch {
            if state == nil {
                phase = .error((error as? APIError)?.localizedDescription ?? error.localizedDescription)
            }
        }
    }

    @discardableResult
    func save(_ req: StylusSaveRequest) async -> Bool {
        guard let settings else { return false }
        do {
            state = try await CatalogService(settings: settings).putStylusProfile(req)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            return true
        } catch {
            actionError = (error as? APIError)?.localizedDescription ?? error.localizedDescription
            return false
        }
    }

    @discardableResult
    func replace(_ req: StylusSaveRequest) async -> Bool {
        guard let settings else { return false }
        do {
            state = try await CatalogService(settings: settings).replaceStylusProfile(req)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            return true
        } catch {
            actionError = (error as? APIError)?.localizedDescription ?? error.localizedDescription
            return false
        }
    }
}
