import Foundation

struct BundledContentLoader {
    enum LoaderError: LocalizedError {
        case missingResource
        case decoding(Error)

        var errorDescription: String? {
            switch self {
            case .missingResource:
                return "تعذر العثور على ملف المنهج داخل التطبيق."
            case .decoding(let underlying):
                if let decodingError = underlying as? DecodingError {
                    return "تعذر قراءة بنية المنهج: \(Self.describe(decodingError))"
                }
                return "تعذر فتح المنهج: \(underlying.localizedDescription)"
            }
        }

        private static func describe(_ error: DecodingError) -> String {
            func path(_ context: DecodingError.Context) -> String {
                context.codingPath.map { $0.intValue.map { "[\($0)]" } ?? $0.stringValue }.joined(separator: ".")
            }
            switch error {
            case .keyNotFound(let key, let context):
                return "الحقل '\(key.stringValue)' غير موجود عند \(path(context))"
            case .typeMismatch(let type, let context):
                return "نوع البيانات غير صحيح (\(type)) عند \(path(context))"
            case .valueNotFound(let type, let context):
                return "قيمة مطلوبة غير موجودة (\(type)) عند \(path(context))"
            case .dataCorrupted(let context):
                return "بيانات غير صالحة عند \(path(context)): \(context.debugDescription)"
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
            let decoded = try JSONDecoder().decode(CourseCatalog.self, from: data)
            return CurriculumEnhancer.enhance(decoded)
        } catch {
            throw LoaderError.decoding(error)
        }
    }
}
