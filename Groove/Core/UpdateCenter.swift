import Foundation
import Observation
import os

/// The connected board's update status, app-wide: the first-use question and the
/// update notices are presented from it, and Settings → Updates reads and changes
/// it. The preference, the approval and the reminders live on the board
/// (groove-updater owns them); this keeps only the last answer read and which
/// install outcome the phone already showed. It also gives the board the phone's
/// time zone, which the board's night install window is read in.
@MainActor
@Observable
final class UpdateCenter {
    /// Nil until the board answers, and on a board without the update service:
    /// nothing about updates shows then.
    private(set) var status: UpdateStatus?

    /// The question was put away without an answer during this connection. It
    /// comes back on the next one (launch, return to the foreground, another board).
    private var questionDeferred = false

    /// The available release whose swiped-away notice is on its way to the board as
    /// "Remind me tomorrow" (`dismiss`); nil otherwise.
    private var remindingRelease: String?

    /// Time zones sent to a board during this app session, taken, refused or still on
    /// their way: each board/zone pair is sent once, so a board that refuses it or has
    /// no route for it is not asked on every read.
    private var timeZoneTried: Set<TimeZoneSend> = []

    private static let log = Logger(subsystem: "com.alemser.groove", category: "updates")

    private var settings: AppSettings?
    private var messages: MessageCenter?
    private var poller: Poller?

    /// How often the status is read while it changes on its own (an install, an
    /// approval waiting for the record to end, a check running). Chosen: an install
    /// goes through downloading, installing and up to 2 minutes of verifying, so 5 s
    /// shows each phase within seconds of the board reaching it, at one small GET
    /// per 5 s only while that lasts.
    static let changingPollInterval: Duration = .seconds(5)

    /// What to put in front of the person now, or nil.
    var notice: UpdateNotice? {
        guard let status, let settings else { return nil }
        return UpdateNotice.next(
            for: status,
            seen: settings.updateNoticeMemory,
            questionDeferred: questionDeferred,
            remindingRelease: remindingRelease
        )
    }

    func configure(_ settings: AppSettings, messages: MessageCenter) {
        self.settings = settings
        self.messages = messages
    }

    /// The app reached a board: at launch, back in the foreground, or after
    /// switching to another board. A different board's status never lingers.
    func connected(boardChanged: Bool = false) async {
        questionDeferred = false
        if boardChanged { status = nil }
        await refresh()
    }

    /// Stops reading the status while the app is in the background.
    func stop() {
        poller?.stop()
        poller = nil
    }

    func refresh() async {
        guard let settings, settings.isConfigured else {
            status = nil
            syncPolling()
            return
        }
        do {
            status = try await CatalogService(settings: settings).updateStatus()
        } catch where error.meansNoUpdater && status?.isChanging != true {
            // No update service on this board. During an install the updater or
            // the catalog restarts, so a refusal then keeps the last status.
            status = nil
        } catch {
            // A transient failure keeps the last status.
        }
        statusRead()
    }

    // MARK: Changes the person asks for

    /// True when the board took the answer.
    @discardableResult
    func setPreference(_ preference: UpdatePreference) async -> Bool {
        await write { try await $0.setUpdatePreference(preference) }
    }

    func checkNow() async {
        await write { try await $0.checkForUpdates() }
    }

    /// Installs the available release as soon as nothing is playing.
    func approve() async {
        guard let release = status?.available?.release else { return }
        await write { try await $0.approveUpdate(release: release) }
    }

    /// Withdrawing is a "not now" for that release: the board puts it off for 24 h,
    /// so its notice doesn't come back at once; Settings still offers it.
    func withdrawApproval() async {
        await write { try await $0.withdrawUpdateApproval() }
    }

    /// "Remind me tomorrow" or "Don't ask again" for the available release.
    func remind(_ remind: UpdateReminder) async {
        guard let release = status?.available?.release else { return }
        await write { try await $0.remindAboutUpdate(release: release, remind) }
    }

    /// The notice was closed without an answer to the board: "OK" for an install's
    /// outcome, or swiped away. Swiping an available release away is "Remind me
    /// tomorrow", so it doesn't come back on every connection.
    func dismiss(_ notice: UpdateNotice) {
        guard let settings else { return }
        switch notice {
        case .question:
            questionDeferred = true
        case let .available(release, _, _):
            // Held closed while the answer travels, so the sheet doesn't present again in between.
            remindingRelease = release
            Task {
                await remind(.tomorrow)
                remindingRelease = nil
            }
        case .installed, .failed:
            settings.updateNoticeMemory.acknowledgedResult = status?.lastResult?.key
        }
    }

    /// Runs one write through `MessageCenter` (a failure is told there, and its
    /// Retry runs this same closure) and takes the status the board answers with.
    @discardableResult
    private func write(_ action: @escaping @MainActor (CatalogService) async throws -> UpdateStatus) async -> Bool {
        guard let settings, let messages else { return false }
        let service = CatalogService(settings: settings)
        return await messages.attempt { [weak self] in
            let updated = try await action(service)
            self?.adopt(updated)
        } != nil
    }

    /// Takes the status a write answered with.
    private func adopt(_ updated: UpdateStatus) {
        status = updated
        statusRead()
    }

    /// A status was read from the board, or the read failed: poll while it changes,
    /// and give the board the phone's time zone when it holds another one.
    private func statusRead() {
        syncPolling()
        sendTimeZoneIfNeeded()
    }

    /// Silent: the person asked for nothing, so a refusal is only logged.
    private func sendTimeZoneIfNeeded() {
        guard let settings, let status,
              let send = TimeZoneSend.next(
                  boardZone: status.timeZone,
                  phoneZone: TimeZone.current.identifier,
                  board: settings.updateBoardKey,
                  tried: timeZoneTried
              )
        else { return }
        timeZoneTried.insert(send)
        let service = CatalogService(settings: settings)
        Task { [weak self] in
            do {
                let updated = try await service.setUpdateTimeZone(send.zone)
                // The answer is about that board: another one may be connected by now.
                guard let self, self.settings?.updateBoardKey == send.board else { return }
                self.adopt(updated)
            } catch {
                Self.log.error("time zone not sent to the board, \(send.zone, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func syncPolling() {
        guard status?.isChanging == true else {
            stop()
            return
        }
        guard poller == nil else { return }
        let p = Poller(interval: Self.changingPollInterval) { [weak self] in await self?.refresh() }
        poller = p
        p.start()
    }
}
