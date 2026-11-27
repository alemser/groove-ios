import Foundation

// MARK: - Board updates (`/system/updates`, groove-updater's status forwarded by groove-catalog)

/// Who decides when the board installs a release. `unset` until someone answers
/// the first-use question; the board checks and installs nothing until then.
enum UpdatePreference: String, Encodable, UnknownTolerantDecodable, Identifiable {
    case unset
    case automatic
    case askFirst = "ask_first"
    case unknown

    var id: Self { self }

    /// The two answers, in the order the first-use question and Settings offer them.
    static let choices: [UpdatePreference] = [.automatic, .askFirst]

    /// The answer preselected in the first-use question: automatic installation
    /// is never the default (groove-system#13).
    static let preselected: UpdatePreference = .askFirst

    var title: String {
        switch self {
        case .automatic: "Install automatically"
        case .askFirst: "Ask me first"
        case .unset, .unknown: ""
        }
    }

    var subtitle: String {
        switch self {
        case .automatic: "When nothing is playing"
        case .askFirst: "The app tells you when a new version is available"
        case .unset, .unknown: ""
        }
    }
}

/// What the updater is doing right now.
enum UpdatePhase: String, UnknownTolerantDecodable {
    case idle
    case checking
    case downloading
    case waitingForIdle = "waiting_for_idle"
    case installing
    case verifying
    case rollingBack = "rolling_back"
    case unknown

    /// The install has touched the board: an approval can no longer be withdrawn.
    /// groove-updater's `Phase.InstallStarted` decides the same, and refuses
    /// `DELETE /approval` from here on.
    var installStarted: Bool {
        switch self {
        case .installing, .verifying, .rollingBack: true
        case .idle, .checking, .downloading, .waitingForIdle, .unknown: false
        }
    }

    /// The release is being fetched, switched in or rolled back: the app reads "Updating…".
    var isInstalling: Bool { self == .downloading || installStarted }
}

/// How the last install ended.
enum UpdateOutcome: String, UnknownTolerantDecodable {
    case installed
    /// The release did not come up; the previous one runs again.
    case rolledBack = "rolled_back"
    /// Even the rollback did not bring the stack up.
    case failed
    case unknown

    var isFailure: Bool { self == .rolledBack || self == .failed }
}

struct UpdateStatus: Decodable, Equatable {
    var preference: UpdatePreference
    var phase: UpdatePhase
    var installed: InstalledRelease
    var available: AvailableRelease?
    var approvedRelease: String
    /// The board asks the person about `available` now: it awaits approval and nobody
    /// put it off ("Remind me tomorrow" less than 24 h ago, "Don't ask again", a
    /// withdrawn approval). The board decides it.
    var askUser: Bool
    var lastCheck: UpdateCheck?
    var lastResult: UpdateResult?
    /// The IANA zone the board reads its night install window in, as a phone sent it
    /// (`PUT /system/updates/time_zone`); `""` until one did.
    var timeZone: String

    struct InstalledRelease: Decodable, Equatable {
        /// `""` on a board written from an image that was not a release.
        var release: String
    }

    struct AvailableRelease: Decodable, Equatable {
        var release: String
        var notes: String
        var security: Bool
    }

    struct UpdateCheck: Decodable, Equatable {
        var at: String
        /// `""` when the check succeeded.
        var error: String
    }

    struct UpdateResult: Decodable, Equatable {
        var release: String
        var outcome: UpdateOutcome
        var at: String
        var notes: String

        /// Tells this install apart from any other, so the phone acknowledges it once.
        var key: String { release + "@" + at }
    }
}

extension UpdateStatus {
    /// Approved and the install not started: the release downloads, or the updater
    /// waits for the board to be idle. The approval can still be withdrawn ("Cancel").
    var isWaitingToInstall: Bool { approvedRelease.nonEmpty != nil && !phase.installStarted }

    /// While this holds the status changes on its own within seconds, so the app
    /// keeps reading it: an install, an approval waiting for idle, a check running.
    var isChanging: Bool { phase.isInstalling || isWaitingToInstall || phase == .checking }

    /// "Update now" applies: a release is offered, nothing is approved or installing,
    /// and the question has an answer (the updater refuses an approval while unset).
    var canApprove: Bool {
        available != nil && approvedRelease.nonEmpty == nil && !phase.isInstalling && preference != .unset
    }

    /// The board's version, for Settings.
    var installedLabel: String { installed.release.nonEmpty ?? "Not a release" }

    /// The one line Settings shows for this status (groove-updater `docs/contracts.md`,
    /// "What the apps show"). Two phones on the same board read the same line: it
    /// depends on the board's state alone, never on what this phone acknowledged.
    var statusLine: String {
        if phase.isInstalling { return "Updating…" }
        if isWaitingToInstall { return "Will install when the record ends" }
        if let available { return "Available: \(available.release)" }
        if let lastResult, lastResult.outcome.isFailure {
            return "Update to \(lastResult.release) failed; the previous version is running"
        }
        if let lastResult, lastResult.outcome == .installed, lastResult.release == installed.release {
            return updatedTo(lastResult.release)
        }
        if lastCheck == nil { return "Not checked yet" }
        return "Up to date"
    }
}

/// An answer to the "Update available" notice that puts the release off
/// (`POST /system/updates/reminder`). The board keeps it, so every phone reads it
/// through `ask_user`.
enum UpdateReminder: String, Encodable {
    /// Ask again about this release in 24 h.
    case tomorrow
    /// Never ask about this release again (a newer one asks). The board refuses it
    /// for a security release.
    case never

    /// The answers the notice offers: a security fix can't be put off for good.
    static func choices(security: Bool) -> [UpdateReminder] {
        security ? [.tomorrow] : [.tomorrow, .never]
    }

    var title: String {
        switch self {
        case .tomorrow: "Remind me tomorrow"
        case .never: "Don't ask again"
        }
    }
}

/// What this phone remembers about one board's updates, so a notice shows once.
struct UpdateNoticeMemory: Equatable {
    /// `UpdateResult.key` of the last install whose outcome was shown.
    var acknowledgedResult: String?
}

/// The one thing the app puts in front of the person about updates when it
/// reaches a board, or nil when there is nothing to say.
enum UpdateNotice: Equatable, Identifiable {
    /// Nobody answered "automatic or ask first" yet.
    case question
    case available(release: String, notes: String, security: Bool)
    case installed(release: String, notes: String)
    case failed(release: String)

    var id: String {
        switch self {
        case .question: "question"
        case let .available(release, _, _): "available-" + release
        case let .installed(release, _): "installed-" + release
        case let .failed(release): "failed-" + release
        }
    }

    var title: String {
        switch self {
        case .question: "Oceano updates"
        case .available: "Update available"
        case let .installed(release, _): updatedTo(release)
        case .failed: "Update didn't work"
        }
    }

    /// The text under the title: the release's notes, or what went wrong.
    var message: String {
        switch self {
        case .question: ""
        case let .available(_, notes, _), let .installed(_, notes): notes
        case let .failed(release): "The update to \(release) didn't work; the previous version is running."
        }
    }

    /// The question first: until it has an answer the board does nothing else.
    /// Then how the last install ended, once per install, then a release the board
    /// asks about (`ask_user`).
    /// `questionDeferred`: the question was put away during this connection.
    /// `remindingRelease`: a reminder for that release is on its way to the board
    /// (the notice was swiped away), so its notice stays closed until the board answers.
    static func next(
        for status: UpdateStatus,
        seen: UpdateNoticeMemory,
        questionDeferred: Bool,
        remindingRelease: String? = nil
    ) -> UpdateNotice? {
        if status.preference == .unset {
            return questionDeferred ? nil : .question
        }
        if let result = status.lastResult, result.key != seen.acknowledgedResult {
            switch result.outcome {
            case .installed: return .installed(release: result.release, notes: result.notes)
            case .rolledBack, .failed: return .failed(release: result.release)
            case .unknown: break
            }
        }
        if status.askUser, let available = status.available, available.release != remindingRelease {
            return .available(release: available.release, notes: available.notes, security: available.security)
        }
        return nil
    }
}

/// The phone's time zone sent to one board (`PUT /system/updates/time_zone`):
/// groove-updater reads its night install window in it.
struct TimeZoneSend: Hashable {
    /// `AppSettings.updateBoardKey` of the board.
    var board: String
    /// IANA name, as `TimeZone.identifier` gives it.
    var zone: String

    /// The send to make now, or nil: the board's zone differs from the phone's and
    /// this pair is not in `tried` (on its way, or refused during this app session),
    /// so a board that refuses the zone is not asked on every read.
    static func next(boardZone: String, phoneZone: String, board: String, tried: Set<TimeZoneSend>) -> TimeZoneSend? {
        guard !phoneZone.isEmpty, boardZone != phoneZone else { return nil }
        let send = TimeZoneSend(board: board, zone: phoneZone)
        return tried.contains(send) ? nil : send
    }
}

/// "Updated to <release>": Settings' status line and the one-time notice say the same.
private func updatedTo(_ release: String) -> String { "Updated to \(release)" }
