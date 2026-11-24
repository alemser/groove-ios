import SwiftUI
import Observation

@MainActor
@Observable
final class RecognitionProvidersModel {
    var state: RecognitionProvidersState?
    var usage: ProviderUsageRollup?
    var phase: Phase = .loading

    enum Phase: Equatable { case loading, loaded, error(String) }

    private var settings: AppSettings?
    private var messages: MessageCenter?

    func configure(_ settings: AppSettings, messages: MessageCenter) {
        if self.settings == nil {
            self.settings = settings
            self.messages = messages
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
                phase = .error(error.localizedForDisplay)
            }
        }
        usage = try? await CatalogService(settings: settings).recognitionObservability()
    }

    func setEnabled(id: String, enabled: Bool) async {
        await apply { try await $0.setRecognitionProviderEnabled(id: id, enabled: enabled) }
    }

    func reorder(_ order: [String]) async {
        await apply { try await $0.reorderRecognitionProviders(order: order) }
    }

    @discardableResult
    func setOffline(_ enabled: Bool) async -> Bool {
        await apply { try await $0.setRecognitionOffline(enabled) }
    }

    @discardableResult
    func saveChainSettings(chainMode: String, minConfidence: Double) async -> Bool {
        await apply { try await $0.patchRecognitionSettings(chainMode: chainMode, minConfidence: minConfidence) }
    }

    @discardableResult
    func saveCredentials(id: String, host: String?, apiKey: String?, apiSecret: String?) async -> Bool {
        await save { try await $0.setRecognitionProviderCredentials(id: id, host: host, apiKey: apiKey, apiSecret: apiSecret) }
    }

    /// True when it went through; a failure is the message center's to tell.
    @discardableResult
    func createCustomProvider(_ req: CustomProviderCreateRequest) async -> Bool {
        await save { try await $0.createCustomProvider(req) }
    }

    @discardableResult
    func updateCustomProvider(slug: String, _ cp: CustomProviderConfig) async -> Bool {
        await save { try await $0.updateCustomProvider(slug: slug, cp) }
    }

    func deleteCustomProvider(slug: String) async {
        guard let settings, let messages else { return }
        await messages.attempt {
            try await CatalogService(settings: settings).deleteCustomProvider(slug: slug)
            await self.load()
        }
    }

    func parseSample(slug: String?, sampleJSON: Data) async throws -> ParseSampleResponse {
        guard let settings else { throw APIError.notConfigured }
        return try await CatalogService(settings: settings).parseSample(slug: slug, sampleJSON: sampleJSON)
    }

    /// A change that answers the new state; on failure the screen reloads what the server holds.
    private func apply(_ request: @escaping (CatalogService) async throws -> RecognitionProvidersState) async -> Bool {
        guard let settings, let messages else { return false }
        let applied = await messages.attempt {
            self.state = try await request(CatalogService(settings: settings))
        } != nil
        if !applied { await load() }
        return applied
    }

    /// A form's save, confirmed with a haptic: the form closes when it returns true.
    private func save(_ request: @escaping (CatalogService) async throws -> RecognitionProvidersState) async -> Bool {
        guard let settings, let messages else { return false }
        return await messages.attempt {
            self.state = try await request(CatalogService(settings: settings))
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } != nil
    }
}
