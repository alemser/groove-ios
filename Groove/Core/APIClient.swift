import Foundation

enum APIError: LocalizedError {
    case notConfigured
    case invalidURL
    case http(status: Int, body: String)
    case decoding(String)
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "No catalog server configured. Add one in Settings."
        case .invalidURL: return "The request URL was invalid."
        case let .http(status, body):
            let detail = body.isEmpty ? "" : " — \(body.prefix(200))"
            return "Server returned \(status)\(detail)"
        case let .decoding(msg): return "Couldn't read the server response: \(msg)"
        case let .transport(msg): return msg
        }
    }
}

/// Thin async HTTP client for the groove-catalog management API. Stateless apart
/// from the injected `AppSettings`, so it is cheap to construct per request.
struct APIClient {
    let settings: AppSettings
    var session: URLSession = .shared

    private func makeURL(_ path: String, query: [URLQueryItem] = []) throws -> URL {
        guard let baseURL = settings.baseURL else { throw APIError.notConfigured }
        guard var comps = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw APIError.invalidURL
        }
        comps.path = path
        comps.queryItems = query.isEmpty ? nil : query
        guard let url = comps.url else { throw APIError.invalidURL }
        return url
    }

    private static let decoder: JSONDecoder = {
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

    @discardableResult
    func patch<Body: Encodable, T: Decodable>(_ path: String, body: Body, as type: T.Type = T.self) async throws -> T {
        try await send(path, method: "PATCH", body: body)
    }

    @discardableResult
    func put<Body: Encodable, T: Decodable>(_ path: String, body: Body, as type: T.Type = T.self) async throws -> T {
        try await send(path, method: "PUT", body: body)
    }

    func delete(_ path: String) async throws {
        _ = try await sendRaw(path, method: "DELETE", body: Optional<Empty>.none)
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

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw APIError.transport(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw APIError.transport("Malformed server response.")
        }
        guard (200..<300).contains(http.statusCode) else {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw APIError.http(status: http.statusCode, body: text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
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

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw APIError.transport(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw APIError.transport("Malformed server response.")
        }
        guard (200..<300).contains(http.statusCode) else {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw APIError.http(status: http.statusCode, body: text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        do {
            return try Self.decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decoding(String(describing: error))
        }
    }

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

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw APIError.transport(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw APIError.transport("Malformed server response.")
        }
        guard (200..<300).contains(http.statusCode) else {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw APIError.http(status: http.statusCode, body: text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return data
    }
}

/// Empty request body sentinel.
struct Empty: Encodable {}
/// Decodable placeholder for endpoints returning no meaningful body.
struct EmptyResponse: Decodable {}
