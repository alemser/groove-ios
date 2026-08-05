import SwiftUI
import Observation

@MainActor
@Observable
final class RecognitionProvidersModel {
    var state: RecognitionProvidersState?
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
            state = try await CatalogService(settings: settings).recognitionProviders()
            phase = .loaded
        } catch {
            if state == nil {
                phase = .error((error as? APIError)?.localizedDescription ?? error.localizedDescription)
            }
        }
    }

    func setEnabled(id: String, enabled: Bool) async {
        guard let settings else { return }
        do {
            state = try await CatalogService(settings: settings).setRecognitionProviderEnabled(id: id, enabled: enabled)
            actionError = nil
        } catch {
            actionError = (error as? APIError)?.localizedDescription ?? error.localizedDescription
            await load()
        }
    }

    func reorder(_ order: [String]) async {
        guard let settings else { return }
        do {
            state = try await CatalogService(settings: settings).reorderRecognitionProviders(order: order)
            actionError = nil
        } catch {
            actionError = (error as? APIError)?.localizedDescription ?? error.localizedDescription
            await load()
        }
    }

    @discardableResult
    func saveCredentials(id: String, host: String?, apiKey: String?, apiSecret: String?) async -> Bool {
        guard let settings else { return false }
        do {
            state = try await CatalogService(settings: settings)
                .setRecognitionProviderCredentials(id: id, host: host, apiKey: apiKey, apiSecret: apiSecret)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            return true
        } catch {
            actionError = (error as? APIError)?.localizedDescription ?? error.localizedDescription
            return false
        }
    }

    @discardableResult
    func saveChainSettings(chainMode: String, minConfidence: Double) async -> Bool {
        guard let settings else { return false }
        do {
            state = try await CatalogService(settings: settings)
                .patchRecognitionSettings(chainMode: chainMode, minConfidence: minConfidence)
            actionError = nil
            return true
        } catch {
            actionError = (error as? APIError)?.localizedDescription ?? error.localizedDescription
            return false
        }
    }

    @discardableResult
    func createCustomProvider(_ req: CustomProviderCreateRequest) async -> String? {
        guard let settings else { return "Not connected." }
        do {
            state = try await CatalogService(settings: settings).createCustomProvider(req)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            return nil
        } catch {
            return (error as? APIError)?.localizedDescription ?? error.localizedDescription
        }
    }

    @discardableResult
    func updateCustomProvider(slug: String, _ cp: CustomProviderConfig) async -> String? {
        guard let settings else { return "Not connected." }
        do {
            state = try await CatalogService(settings: settings).updateCustomProvider(slug: slug, cp)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            return nil
        } catch {
            return (error as? APIError)?.localizedDescription ?? error.localizedDescription
        }
    }

    func deleteCustomProvider(slug: String) async {
        guard let settings else { return }
        do {
            try await CatalogService(settings: settings).deleteCustomProvider(slug: slug)
            await load()
        } catch {
            actionError = (error as? APIError)?.localizedDescription ?? error.localizedDescription
        }
    }

    func parseSample(slug: String?, sampleJSON: Data) async throws -> ParseSampleResponse {
        guard let settings else { throw APIError.notConfigured }
        return try await CatalogService(settings: settings).parseSample(slug: slug, sampleJSON: sampleJSON)
    }
}
