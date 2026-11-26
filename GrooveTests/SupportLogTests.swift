import XCTest
@testable import Groove

/// The board's support log: groove-updater's `GET /logs`, through the catalog's
/// `/system/logs`, as the app downloads it.
final class SupportLogTests: XCTestCase {
    override func tearDown() {
        StubProtocol.answer = nil
        super.tearDown()
    }

    /// The catalog route CatalogService.supportLog reads.
    private func download() async throws -> DownloadedFile {
        var api = APIClient(baseURL: URL(string: "http://oceano.test:7073")!)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        api.session = URLSession(configuration: config)
        return try await api.download("/system/logs")
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

    func testABoardWithoutTheUpdaterAnswersWithAnError() async {
        StubProtocol.answer = (502, [:], Data("updater unreachable\n".utf8))
        do {
            _ = try await download()
            XCTFail("a 502 read as a log")
        } catch APIError.http(let status, let body) {
            XCTAssertEqual(status, 502)
            XCTAssertEqual(body, "updater unreachable")
        } catch {
            XCTFail("\(error)")
        }
    }

    func testAFileNameThatCouldLeaveTheDirectoryIsDropped() {
        XCTAssertEqual(attachmentName("attachment; filename=\"a.log.gz\""), "a.log.gz")
        for header in ["attachment; filename=..", "attachment; filename=\"../x\"", "attachment", nil] {
            XCTAssertNil(attachmentName(header), String(describing: header))
        }
    }
}

/// Answers every request with `answer`, and records the path asked for.
private final class StubProtocol: URLProtocol {
    nonisolated(unsafe) static var answer: (status: Int, headers: [String: String], body: Data)?
    nonisolated(unsafe) static var lastPath: String?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastPath = request.url?.path
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
