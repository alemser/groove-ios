import Foundation

enum APIError: LocalizedError {
    case notConfigured
    case invalidURL
    case http(status: Int, body: String)
    case decoding(String)
    case transport(String)
    /// Nothing answered at the address: refused, no such name, or no reply in
    /// time. A board that moved to another address or network fails this way
    /// (groove-system#10). groove-android says the same.
    case unanswered

    /// The URLSession failures that mean `unanswered`.
    static let unansweredCodes: Set<URLError.Code> = [.cannotConnectToHost, .cannotFindHost, .dnsLookupFailed, .timedOut]

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "No catalog server configured. Add one in Settings."
        case .invalidURL: return "The request URL was invalid."
        case let .http(status, body):
            let detail = body.isEmpty ? "" : " — \(body.prefix(200))"
            return "Server returned \(status)\(detail)"
        case let .decoding(msg): return "Couldn't read the server response: \(msg)"
        case let .transport(msg): return msg
        case .unanswered: return "Oceano isn't answering. Check that it's on and on the same Wi-Fi as this phone."
        }
    }
}

extension Error {
    /// User-facing message for any error surfaced from `CatalogService`/`APIClient`
    /// — the one place this app decides how an error reads on screen, instead of
    /// every call site repeating `(error as? APIError)?.localizedDescription ??
    /// error.localizedDescription`. groove-catalog and groove-rig answer errors as
    /// `{"error": "…"}`; that sentence reads, not the JSON.
    var localizedForDisplay: String {
        if case let .http(_, body)? = self as? APIError, let sentence = decodeRefusal(body)?.error?.nonEmpty {
            return sentence
        }
        return (self as? APIError)?.localizedDescription ?? localizedDescription
    }

    /// The board has no update service to reach: an older groove-catalog without the
    /// `/system/updates` routes answers 404 or 405, and one whose groove-updater is off
    /// or unreachable answers 503 or 502. The app then shows nothing about updates.
    var meansNoUpdater: Bool {
        guard case let .http(status, _)? = self as? APIError else { return false }
        return noUpdaterStatuses.contains(status)
    }

    /// The release check's refusal this error is, or nil for any other error. A
    /// refusal whose body didn't decode still counts: it says only that the check failed.
    var refusal: ConfirmPreflightError? {
        guard case let .http(status, body)? = self as? APIError, status == httpUnprocessable else { return nil }
        return decodeRefusal(body) ?? ConfirmPreflightError()
    }
}

/// The status groove-catalog answers when its release check refuses a tracklist.
private let httpUnprocessable = 422

/// Not found, method not allowed, bad gateway, service unavailable: see `meansNoUpdater`.
private let noUpdaterStatuses: Set<Int> = [404, 405, 502, 503]

/// The refusal body of a failed confirm or save, when the server sent one.
func decodeRefusal(_ body: String) -> ConfirmPreflightError? {
    try? APIClient.decoder.decode(ConfirmPreflightError.self, from: Data(body.utf8))
}

extension ConfirmPreflightError {
    /// The refusal's sentence, then what the check found, one per line.
    var explanation: String {
        let issues = (preflightIssues ?? []).compactMap { $0.message?.nonEmpty }.joined(separator: "\n")
        return [error?.nonEmpty ?? "The tracklist failed the release check.", issues.nonEmpty]
            .compactMap { $0 }
            .joined(separator: "\n\n")
    }
}

/// Thin async HTTP client for the groove-catalog management API, and for the
/// board's Wi-Fi setup routes (`WifiSetupClient`). Stateless apart from where
/// it sends requests, so it is cheap to construct per request.
struct APIClient {
    /// Read on every request: the catalog's address can change in Settings.
    let baseURL: () -> URL?
    var session: URLSession = .shared

    init(settings: AppSettings) {
        baseURL = { settings.baseURL }
    }

    init(baseURL: URL) {
        self.baseURL = { baseURL }
    }

    /// `path` keeps the encoding `pathSegment` gave it. Assigning it to
    /// `URLComponents.path` would encode the `%` a second time, and assigning
    /// `percentEncodedPath` traps on an invalid escape; resolving against the base
    /// URL does neither. Query parameters go in `query`, never in `path`.
    private func makeURL(_ path: String, query: [URLQueryItem] = []) throws -> URL {
        guard let baseURL = baseURL() else { throw APIError.notConfigured }
        guard let resolved = URL(string: path, relativeTo: baseURL)?.absoluteURL,
              var comps = URLComponents(url: resolved, resolvingAgainstBaseURL: false) else {
            throw APIError.invalidURL
        }
        comps.queryItems = query.isEmpty ? nil : query
        guard let url = comps.url else { throw APIError.invalidURL }
        return url
    }

    /// How every catalog answer is decoded, error bodies and test fixtures included.
    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        return e
    }()

    // MARK: - Verbs

    func get<T: Decodable>(_ path: String, query: [URLQueryItem] = [], as type: T.Type = T.self) async throws -> T {
        try await send(path, method: "GET", query: query, body: Optional<Empty>.none)
    }

    @discardableResult
    func post<Body: Encodable, T: Decodable>(_ path: String, query: [URLQueryItem] = [], body: Body, as type: T.Type = T.self) async throws -> T {
        try await send(path, method: "POST", query: query, body: body)
    }

    func postNoContent(_ path: String) async throws {
        _ = try await sendRaw(path, method: "POST", body: Optional<Empty>.none)
    }

    /// POST with a body to an endpoint that answers 204. Distinct from `post`,
    /// which requires a decodable response the caller does not have.
    func postNoContent<Body: Encodable>(_ path: String, body: Body) async throws {
        _ = try await sendRaw(path, method: "POST", body: body)
    }

    @discardableResult
    func patch<Body: Encodable, T: Decodable>(_ path: String, body: Body, as type: T.Type = T.self) async throws -> T {
        try await send(path, method: "PATCH", body: body)
    }

    @discardableResult
    func put<Body: Encodable, T: Decodable>(_ path: String, query: [URLQueryItem] = [], body: Body, as type: T.Type = T.self) async throws -> T {
        try await send(path, method: "PUT", query: query, body: body)
    }

    func delete(_ path: String, query: [URLQueryItem] = []) async throws {
        _ = try await sendRaw(path, method: "DELETE", query: query, body: Optional<Empty>.none)
    }

    /// DELETE to an endpoint that answers with a body the caller reads.
    func delete<T: Decodable>(_ path: String, as type: T.Type) async throws -> T {
        try await send(path, method: "DELETE", body: Optional<Empty>.none)
    }

    /// Posts a pre-built raw JSON body, bypassing the `Encodable` encoder — for the one
    /// endpoint (`parse-sample`) that takes an arbitrary user-supplied JSON value inline
    /// rather than a typed request shape.
    func postRawJSON<T: Decodable>(_ path: String, jsonBody: Data, as type: T.Type = T.self) async throws -> T {
        let url = try makeURL(path)
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 20
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = jsonBody
        let data = try await execute(req)
        do {
            return try Self.decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decoding(String(describing: error))
        }
    }

    /// Uploads one file as `multipart/form-data` — for the one endpoint (release
    /// artwork) that takes a binary upload rather than a JSON body.
    func postMultipart<T: Decodable>(
        _ path: String,
        fieldName: String,
        filename: String,
        mimeType: String,
        data fileData: Data,
        as type: T.Type = T.self
    ) async throws -> T {
        let url = try makeURL(path)
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 30
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        let boundary = "Boundary-\(UUID().uuidString)"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"\(fieldName)\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        req.httpBody = body
        let data = try await execute(req)
        do {
            return try Self.decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decoding(String(describing: error))
        }
    }

    /// GETs a file: its bytes and the name the server gives it. Asked for once: the
    /// one file is the support log, which the board builds again for each request,
    /// and Share Logs has a Retry.
    func download(_ path: String) async throws -> DownloadedFile {
        var req = URLRequest(url: try makeURL(path))
        req.httpMethod = "GET"
        req.timeoutInterval = Self.downloadTimeout
        let (data, response) = try await executeResponse(req, maxAttempts: 1)
        return DownloadedFile(name: attachmentName(response.value(forHTTPHeaderField: "Content-Disposition")), data: data)
    }

    /// Chosen: the support log is the slowest answer, bounded by groove-catalog's
    /// 30 s write timeout; 10 s more for the LAN.
    private static let downloadTimeout: TimeInterval = 40

    // MARK: - Core

    private func send<Body: Encodable, T: Decodable>(
        _ path: String,
        method: String,
        query: [URLQueryItem] = [],
        body: Body?
    ) async throws -> T {
        let data = try await sendRaw(path, method: method, query: query, body: body)
        if T.self == EmptyResponse.self {
            return EmptyResponse() as! T
        }
        do {
            return try Self.decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decoding(String(describing: error))
        }
    }

    @discardableResult
    private func sendRaw<Body: Encodable>(
        _ path: String,
        method: String,
        query: [URLQueryItem] = [],
        body: Body?
    ) async throws -> Data {
        let url = try makeURL(path, query: query)
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 20
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try Self.encoder.encode(body)
        }
        return try await execute(req)
    }

    /// Single choke point every request runs through. GET is safe to repeat,
    /// so a transient transport failure gets a couple of retries with rising
    /// backoff. This app's `host` is stored as a Bonjour `.local` hostname
    /// (deliberately, see CatalogDiscovery — an IP wouldn't survive a DHCP
    /// lease change), and resolving that over mDNS is known to be flaky on
    /// the very first request right after a cold app launch: the OS's mDNS
    /// resolver hasn't been "primed" the way it is when the user explicitly
    /// browses in Settings → Switch Server, so the first attempt can fail
    /// outright rather than just being slow. Three attempts (500ms, then
    /// 1000ms backoff) gives that resolution a beat to catch up instead of
    /// surfacing a false "something went wrong" on every launch. Writes
    /// (POST/PATCH/PUT/DELETE) never retry here: replaying one after an
    /// ambiguous failure could double-apply it. A non-2xx HTTP response is a
    /// real answer from the server, not a transient failure, and is never
    /// retried either way.
    private func execute(_ req: URLRequest) async throws -> Data {
        try await executeResponse(req).data
    }

    /// `execute`, keeping the response for its headers.
    private func executeResponse(
        _ req: URLRequest,
        maxAttempts: Int? = nil
    ) async throws -> (data: Data, response: HTTPURLResponse) {
        let maxAttempts = maxAttempts ?? (req.httpMethod == "GET" ? 3 : 1)
        var lastTransportError = APIError.transport("Unknown transport error.")
        for attempt in 1...maxAttempts {
            do {
                let (data, response) = try await session.data(for: req)
                guard let http = response as? HTTPURLResponse else {
                    throw APIError.transport("Malformed server response.")
                }
                guard (200..<300).contains(http.statusCode) else {
                    let text = String(data: data, encoding: .utf8) ?? ""
                    throw APIError.http(status: http.statusCode, body: text.trimmingCharacters(in: .whitespacesAndNewlines))
                }
                return (data, http)
            } catch let error as APIError {
                throw error
            } catch {
                if let urlError = error as? URLError, APIError.unansweredCodes.contains(urlError.code) {
                    lastTransportError = .unanswered
                } else {
                    lastTransportError = .transport(error.localizedDescription)
                }
                if attempt < maxAttempts {
                    try? await Task.sleep(for: .milliseconds(500 * attempt))
                }
            }
        }
        throw lastTransportError
    }
}

/// A file the server sent: its bytes and the name it gave it, nil when none or not a plain one.
struct DownloadedFile {
    let name: String?
    let data: Data
}

/// The file name of a `Content-Disposition: attachment; filename=...` header, quoted or not.
/// Only a plain name (a letter or digit, then letters, digits, `.`, `_`, `-`) is kept: it
/// names a file the app writes.
func attachmentName(_ header: String?) -> String? {
    guard let header, let range = header.range(of: "filename=") else { return nil }
    let raw = header[range.upperBound...]
        .prefix { $0 != ";" }
        .trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
    guard let first = raw.unicodeScalars.first, plainFileNameStart.contains(first),
          raw.unicodeScalars.allSatisfy(plainFileNameCharacters.contains) else { return nil }
    return raw
}

private let plainFileNameStart = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
private let plainFileNameCharacters = plainFileNameStart.union(CharacterSet(charactersIn: "._-"))

/// Empty request body sentinel.
struct Empty: Encodable {}
/// Decodable placeholder for endpoints returning no meaningful body.
struct EmptyResponse: Decodable {}
