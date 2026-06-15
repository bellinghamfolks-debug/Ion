import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct NetworkResponse {
    let data: Data
    let response: HTTPURLResponse

    var statusCode: Int { response.statusCode }

    var retryAfter: TimeInterval? {
        guard let value = response.value(forHTTPHeaderField: "Retry-After")?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        if let seconds = TimeInterval(value) { return max(0, seconds) }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        for format in ["EEE',' dd MMM yyyy HH':'mm':'ss zzz", "EEEE',' dd-MMM-yy HH':'mm':'ss zzz"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: value) {
                return max(0, date.timeIntervalSinceNow)
            }
        }
        return nil
    }
}

enum NetworkTransport {
    static let maximumResponseBytes = 32 * 1_024 * 1_024

    static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        #if !canImport(FoundationNetworking)
        config.waitsForConnectivity = true
        #endif
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        config.httpMaximumConnectionsPerHost = 4
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 600
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        return URLSession(configuration: config)
    }()

    static func data(for request: URLRequest) async throws -> NetworkResponse {
        try Task.checkCancellation()
        do {
            let (data, response) = try await session.data(for: request)
            return try checked(data: data, response: response)
        } catch is CancellationError {
            throw GeminiError.cancelled
        } catch let error as URLError where error.code == .cancelled {
            throw GeminiError.cancelled
        } catch let error as GeminiError {
            throw error
        } catch {
            throw GeminiError.network(error)
        }
    }

    static func upload(for request: URLRequest, fromFile fileURL: URL) async throws -> NetworkResponse {
        try Task.checkCancellation()
        do {
            let (data, response) = try await session.upload(for: request, fromFile: fileURL)
            return try checked(data: data, response: response)
        } catch is CancellationError {
            throw GeminiError.cancelled
        } catch let error as URLError where error.code == .cancelled {
            throw GeminiError.cancelled
        } catch let error as GeminiError {
            throw error
        } catch {
            throw GeminiError.network(error)
        }
    }

    static func upload(for request: URLRequest, from data: Data) async throws -> NetworkResponse {
        try Task.checkCancellation()
        do {
            let (responseData, response) = try await session.upload(for: request, from: data)
            return try checked(data: responseData, response: response)
        } catch is CancellationError {
            throw GeminiError.cancelled
        } catch let error as URLError where error.code == .cancelled {
            throw GeminiError.cancelled
        } catch let error as GeminiError {
            throw error
        } catch {
            throw GeminiError.network(error)
        }
    }

    static func safeProxyEndpoint(from rawValue: String) -> URL? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed),
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil else { return nil }

        let isLocal = host == "localhost" || host == "127.0.0.1" || host == "::1"
        guard components.scheme?.lowercased() == "https" ||
              (isLocal && components.scheme?.lowercased() == "http") else { return nil }

        var path = components.path
        while path.hasSuffix("/") { path.removeLast() }
        if !path.hasSuffix("/api/basir") { path += "/api/basir" }
        components.path = path
        components.query = nil
        components.fragment = nil
        return components.url
    }

    static func boundedBody(_ data: Data, limit: Int = 2_000) -> String {
        String(String(data: data, encoding: .utf8)?.prefix(limit) ?? "")
    }

    private static func checked(data: Data, response: URLResponse) throws -> NetworkResponse {
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else {
            throw GeminiError.network(URLError(.badServerResponse))
        }
        guard data.count <= maximumResponseBytes else {
            throw GeminiError.decode("server response exceeded the safe size limit")
        }
        return NetworkResponse(data: data, response: http)
    }
}
