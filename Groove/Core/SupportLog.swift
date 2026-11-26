import Foundation

/// Downloads the board's support log into the app's temporary directory and
/// returns the file, for the share sheet: the person sends it where they
/// choose. Only the latest log is kept.
func downloadSupportLog(_ service: CatalogService) async throws -> URL {
    let log = try await service.supportLog()
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(supportLogDirectory, isDirectory: true)
    try? FileManager.default.removeItem(at: dir)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let file = dir.appendingPathComponent(log.name ?? supportLogFallbackName)
    try log.data.write(to: file)
    return file
}

private let supportLogDirectory = "support-log"
private let supportLogFallbackName = "oceano.log.gz"
