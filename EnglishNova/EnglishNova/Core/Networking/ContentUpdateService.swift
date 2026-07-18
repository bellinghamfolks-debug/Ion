import CryptoKit
import Foundation

struct RemoteContentManifest: Codable {
    let version: Int
    let minimumAppVersion: String
    let publishedAt: Date?
    let notesAr: String
    let curriculumURL: URL
    let sha256: String
}

enum ContentUpdateError: LocalizedError {
    case insecureURL
    case checksumMismatch
    case packageTooLarge
    case invalidCatalog
    case unavailableStorage

    var errorDescription: String? {
        switch self {
        case .insecureURL: return L("رابط حزمة المحتوى يجب أن يستخدم HTTPS.")
        case .checksumMismatch: return L("فشل التحقق من سلامة حزمة المحتوى.")
        case .packageTooLarge: return L("حزمة المحتوى أكبر من الحد الآمن.")
        case .invalidCatalog: return L("الحزمة لا تحتوي منهجًا صالحًا.")
        case .unavailableStorage: return L("تعذر الوصول إلى مساحة التخزين المحلية.")
        }
    }
}

actor ContentUpdateService {
    private let apiClient: APIClient
    private let decoder: JSONDecoder = {
        let value = JSONDecoder()
        value.dateDecodingStrategy = .iso8601
        return value
    }()

    init(apiClient: APIClient) { self.apiClient = apiClient }

    func check() async throws -> RemoteContentManifest {
        try await apiClient.get(path: "v1/content/manifest", response: RemoteContentManifest.self)
    }

    func install(_ manifest: RemoteContentManifest) async throws -> CourseCatalog {
        guard manifest.curriculumURL.scheme?.lowercased() == "https" else { throw ContentUpdateError.insecureURL }
        let (data, response) = try await URLSession.shared.data(from: manifest.curriculumURL)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw APIError.invalidResponse
        }
        guard data.count <= 15 * 1_024 * 1_024 else { throw ContentUpdateError.packageTooLarge }
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard digest.caseInsensitiveCompare(manifest.sha256) == .orderedSame else {
            throw ContentUpdateError.checksumMismatch
        }
        guard let catalog = try? decoder.decode(CourseCatalog.self, from: data), !catalog.levels.isEmpty else {
            throw ContentUpdateError.invalidCatalog
        }
        try ContentPaths.prepare()
        guard let destination = ContentPaths.activeCurriculumURL else { throw ContentUpdateError.unavailableStorage }
        try data.write(to: destination, options: [.atomic, .completeFileProtection])
        return catalog
    }
}
