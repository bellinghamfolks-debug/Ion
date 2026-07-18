import Foundation

struct APIConfiguration {
    let baseURL: URL?
    var timeout: TimeInterval = 30
}

enum APIError: LocalizedError {
    case missingBaseURL
    case insecureBaseURL
    case responseTooLarge
    case invalidResponse
    case server(status: Int, message: String)
    case decoding(Error)

    var errorDescription: String? {
        switch self {
        case .missingBaseURL: return L("لم يتم تعيين عنوان الخادم.")
        case .insecureBaseURL: return L("عنوان الخادم يجب أن يكون HTTPS صالحًا.")
        case .responseTooLarge: return L("استجابة الخادم أكبر من الحد الآمن.")
        case .invalidResponse: return L("استجابة غير صالحة من الخادم.")
        case let .server(status, message): return "خطأ خادم رقم \(status): \(message)"
        case let .decoding(error): return "تعذر قراءة الاستجابة: \(error.localizedDescription)"
        }
    }
}

struct EmptyBody: Encodable {}

final class APIClient {
    private let configuration: APIConfiguration
    private let session: URLSession
    private let encoder = JSONEncoder()
    private let decoder: JSONDecoder = {
        let value = JSONDecoder()
        value.dateDecodingStrategy = .iso8601
        return value
    }()

    init(configuration: APIConfiguration) {
        self.configuration = configuration
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = configuration.timeout
        config.waitsForConnectivity = true
        self.session = URLSession(configuration: config)
    }

    func get<Response: Decodable>(path: String, response: Response.Type,
                                  bearerToken: String? = nil) async throws -> Response {
        try await send(path: path, method: "GET", body: Optional<EmptyBody>.none,
                       response: response, bearerToken: bearerToken)
    }

    func send<Response: Decodable, Body: Encodable>(
        path: String,
        method: String = "GET",
        body: Body? = nil,
        response: Response.Type,
        bearerToken: String? = nil
    ) async throws -> Response {
        guard let baseURL = ServerEndpoint.currentURL ?? configuration.baseURL else { throw APIError.missingBaseURL }
        guard baseURL.scheme?.lowercased() == "https", baseURL.host != nil else { throw APIError.insecureBaseURL }
        let url = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let bearerToken { request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization") }
        if let body { request.httpBody = try encoder.encode(body) }

        let (data, urlResponse) = try await session.data(for: request)
        guard data.count <= 10 * 1_024 * 1_024 else { throw APIError.responseTooLarge }
        guard let http = urlResponse as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let rawMessage = String(data: data.prefix(1_000), encoding: .utf8) ?? "Unknown"
            throw APIError.server(status: http.statusCode, message: rawMessage)
        }
        do { return try decoder.decode(Response.self, from: data) }
        catch { throw APIError.decoding(error) }
    }
}
