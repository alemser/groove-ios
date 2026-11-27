import XCTest
@testable import Groove

/// The board's support log: groove-updater's `GET /logs`, through the catalog's
/// `/system/logs`, as the app downloads it.
final class SupportLogTests: XCTestCase {
    override func tearDown() {
        StubProtocol.answer = nil
        StubProtocol.requestCount = 0
        super.tearDown()
    }

    /// The catalog route CatalogService.supportLog reads.
    private func download() async throws -> DownloadedFile {
        var api = APIClient(baseURL: URL(string: "http://\(StubProtocol.host):7073")!)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        api.session = URLSession(configuration: config)
        return try await api.download("/system/logs")
    }

    /// `CatalogService.supportLog()` as Settings calls it, against the stub. The settings
    /// live in the test host's defaults, so the host there before is put back.
    private func catalogSupportLog() async throws -> DownloadedFile {
        let settings = AppSettings()
        let previousHost = settings.host
        settings.host = StubProtocol.host
        URLProtocol.registerClass(StubProtocol.self)
        defer {
            URLProtocol.unregisterClass(StubProtocol.self)
            settings.host = previousHost
        }
        return try await CatalogService(settings: settings).supportLog()
    }

    func testTheLogKeepsItsBytesAndTheBoardsFileName() async throws {
        let gzip = Data([0x1f, 0x8b, 8, 0, 0, 0, 0, 0, 0, 0xff])
        StubProtocol.answer = (200, ["Content-Type": "application/gzip",
            "Content-Disposition": "attachment; filename=oceano-4bf2-20261126-101230.log.gz"], gzip)
        let log = try await download()
        XCTAssertEqual(StubProtocol.lastPath, "/system/logs")
        XCTAssertEqual(log.name, "oceano-4bf2-20261126-101230.log.gz")
        XCTAssertEqual(log.data, gzip)
    }

    /// groove-catalog's answers without the updater: updater off or down (503, 502).
    func testABoardWithoutTheUpdaterSaysInPlainWordsItCantMakeALog() async {
        for status in [502, 503] {
            StubProtocol.answer = (status, [:], Data("updater unreachable\n".utf8))
            do {
                _ = try await catalogSupportLog()
                XCTFail("a \(status) read as a log")
            } catch {
                XCTAssertEqual(error.localizedForDisplay, "This Oceano can't make a support log right now: its update service isn't running.", "\(status)")
            }
        }
    }

    /// Each try makes the board gather two days of its journal again; Share Logs has its own Retry.
    func testTheLogIsAskedForOnceEvenAfterATransportFailure() async {
        StubProtocol.answer = nil // the connection fails
        do {
            _ = try await download()
            XCTFail("a failed connection read as a log")
        } catch {
            XCTAssertEqual(StubProtocol.requestCount, 1)
        }
    }

    func testAFileNameThatCouldLeaveTheDirectoryIsDropped() {
        XCTAssertEqual(attachmentName("attachment; filename=\"a.log.gz\""), "a.log.gz")
        for header in ["attachment; filename=..", "attachment; filename=\"../x\"", "attachment", nil] {
            XCTAssertNil(attachmentName(header), String(describing: header))
        }
    }
}

/// Answers every request to `host` with `answer` (no answer: the connection fails), and
/// records the path asked for and how many requests came.
private final class StubProtocol: URLProtocol {
    static let host = "oceano.test"
    nonisolated(unsafe) static var answer: (status: Int, headers: [String: String], body: Data)?
    nonisolated(unsafe) static var lastPath: String?
    nonisolated(unsafe) static var requestCount = 0

    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == host }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastPath = request.url?.path
        Self.requestCount += 1
        guard let answer = Self.answer, let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: answer.status, httpVersion: nil, headerFields: answer.headers) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: answer.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
