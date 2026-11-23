import Foundation
import Observation

/// One thing to tell the person: an action that failed, or a short acknowledgement. A screen
/// whose own data didn't load keeps `ErrorStateView`, and a wrong form value stays under its field.
struct Message: Identifiable {
    let id = UUID()
    let text: String
    let isError: Bool
    var retry: (@MainActor () async -> Void)? = nil
}

/// The app's one channel for messages. They show one at a time, in order, as a banner in a
/// window of their own above every sheet (`MessageBannerWindow`). Android has the same API
/// (`MessageCenter.kt`); only the presentation differs.
@MainActor
@Observable
final class MessageCenter {
    private var queue: [Message] = []

    /// The message on screen, until it times out or is dismissed.
    var current: Message? { queue.first }

    /// An action failed. The text is `localizedForDisplay`'s: no screen words an error itself.
    func error(_ error: Error, retry: (@MainActor () async -> Void)? = nil) {
        post(Message(text: error.localizedForDisplay, isError: true, retry: retry))
    }

    /// An action failed on the phone itself, with no error to word.
    func error(_ text: String) {
        post(Message(text: text, isError: true))
    }

    func info(_ text: String) {
        post(Message(text: text, isError: false))
    }

    func dismiss(_ message: Message) {
        queue.removeAll { $0.id == message.id }
    }

    /// Runs something the person asked for: its result, or nil when it failed. A failure is
    /// told here, and its Retry runs the same thing again.
    @discardableResult
    func attempt<T>(_ action: @escaping @MainActor () async throws -> T) async -> T? {
        do {
            return try await action()
        } catch {
            self.error(error, retry: { [weak self] in await self?.attempt(action) })
            return nil
        }
    }

    /// The same text already waiting or on screen isn't queued again: five taps on a rig
    /// that doesn't answer say so once.
    private func post(_ message: Message) {
        guard !queue.contains(where: { $0.text == message.text && $0.isError == message.isError }) else { return }
        queue.append(message)
    }
}
