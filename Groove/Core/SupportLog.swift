import Foundation

/// Why Share Logs didn't get to the share sheet, in the words the person reads.
/// Android says the same.
enum SupportLogError: LocalizedError {
    /// The board's updater, which makes the log, is off or doesn't answer.
    case unavailable
    /// The phone couldn't keep the file.
    case onPhone

    var errorDescription: String? {
        switch self {
        case .unavailable: "This Oceano can't make a support log right now: its update service isn't running."
        case .onPhone: "This phone couldn't prepare the log to share."
        }
    }
}

/// Downloads the board's support log into the app's temporary directory and
/// returns the file, for the share sheet: the person sends it where they
/// choose. Only the latest log is kept.
func downloadSupportLog(_ service: CatalogService) async throws -> URL {
    let log = try await service.supportLog()
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(supportLogDirectory, isDirectory: true)
    do {
        try? FileManager.default.removeItem(at: dir)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent(log.name ?? supportLogFallbackName)
        try log.data.write(to: file)
        return file
    } catch {
        throw SupportLogError.onPhone
    }
}

private let supportLogDirectory = "support-log"
private let supportLogFallbackName = "oceano.log.gz"
