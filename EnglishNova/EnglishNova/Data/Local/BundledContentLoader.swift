import Foundation

struct BundledContentLoader {
    enum LoaderError: LocalizedError {
        case missingResource
        case decoding(Error)

        var errorDescription: String? {
            switch self {
            case .missingResource:
                return "ملف المنهج غير موجود داخل حزمة التطبيق (curriculum.json)."
            case .decoding(let underlying):
                if let decodingError = underlying as? DecodingError {
                    return "تعذّر فك ترميز المنهج: \(Self.describe(decodingError))"
                }
                return "تعذّر قراءة المنهج: \(underlying.localizedDescription)"
            }
        }

        private static func describe(_ error: DecodingError) -> String {
            func path(_ context: DecodingError.Context) -> String {
                context.codingPath.map { $0.intValue.map { "[\($0)]" } ?? $0.stringValue }.joined(separator: ".")
            }
            switch error {
            case .keyNotFound(let key, let context):
                return "مفتاح مفقود '\(key.stringValue)' عند \(path(context))"
            case .typeMismatch(let type, let context):
                return "نوع غير متطابق (\(type)) عند \(path(context))"
            case .valueNotFound(let type, let context):
                return "قيمة مفقودة (\(type)) عند \(path(context))"
            case .dataCorrupted(let context):
                return "بيانات تالفة عند \(path(context)): \(context.debugDescription)"
            @unknown default:
                return String(describing: error)
            }
        }
    }

    func loadCatalog() throws -> CourseCatalog {
        let bundledURL = Bundle.main.url(forResource: "curriculum", withExtension: "json", subdirectory: "Curriculum")
            ?? Bundle.main.url(forResource: "curriculum", withExtension: "json")
        let url: URL
        if let active = ContentPaths.activeCurriculumURL, FileManager.default.fileExists(atPath: active.path) {
            url = active
        } else if let bundledURL {
            url = bundledURL
        } else {
            throw LoaderError.missingResource
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(CourseCatalog.self, from: data)
        } catch {
            throw LoaderError.decoding(error)
        }
    }
}
