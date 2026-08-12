import Foundation

struct AudioClipDescriptor: Identifiable, Codable, Hashable {
    let id: String
    let text: String
    let relativePath: String
    let remoteURL: URL
    let sha256: String?
}

struct AudioPackDescriptor: Identifiable, Codable, Hashable {
    let id: String
    let titleAr: String
    let titleEn: String
    let level: CEFRLevel
    let voiceName: String
    let approximateBytes: Int64
    let version: Int
    let clips: [AudioClipDescriptor]
}

struct AudioPackIndex: Codable, Hashable {
    let version: Int
    let packs: [AudioPackDescriptor]
}

enum AudioPackState: Equatable {
    case notDownloaded
    case downloading(progress: Double)
    case ready(size: Int64)
    case failed(String)

    var accessibilityDescription: String {
        switch self {
        case .notDownloaded: return "غير محمّلة"
        case let .downloading(progress): return "جارٍ التنزيل بنسبة \(Int(progress * 100)) بالمئة"
        case let .ready(size): return "جاهزة دون إنترنت، الحجم \(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))"
        case let .failed(message): return "تعذر التنزيل: \(message)"
        }
    }
}
