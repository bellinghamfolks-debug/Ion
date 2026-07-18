import Foundation

actor FileStore {
    enum StoreError: LocalizedError {
        case invalidDirectory
        case invalidPath

        var errorDescription: String? {
            switch self {
            case .invalidDirectory: return L("تعذر الوصول إلى مجلد تخزين التطبيق.")
            case .invalidPath: return L("مسار التخزين المطلوب غير آمن.")
            }
        }
    }

    private let encoder: JSONEncoder = {
        let value = JSONEncoder()
        value.outputFormatting = [.prettyPrinted, .sortedKeys]
        value.dateEncodingStrategy = .iso8601
        return value
    }()

    private let decoder: JSONDecoder = {
        let value = JSONDecoder()
        value.dateDecodingStrategy = .iso8601
        return value
    }()

    func url(for name: String) throws -> URL {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw StoreError.invalidDirectory
        }
        let folder = base.appendingPathComponent("EnglishNova", isDirectory: true).standardizedFileURL
        let components = name.split(separator: "/", omittingEmptySubsequences: false)
        guard !name.isEmpty,
              !name.hasPrefix("/"),
              !name.contains("\0"),
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw StoreError.invalidPath
        }
        let destination = folder.appendingPathComponent(name).standardizedFileURL
        let rootPrefix = folder.path.hasSuffix("/") ? folder.path : folder.path + "/"
        guard destination.path.hasPrefix(rootPrefix) else { throw StoreError.invalidPath }
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        return destination
    }

    func write<T: Encodable>(_ value: T, to name: String) throws {
        let data = try encoder.encode(value)
        try writeData(data, to: name)
    }

    func read<T: Decodable>(_ type: T.Type, from name: String) throws -> T {
        let data = try readData(from: name)
        return try decoder.decode(type, from: data)
    }

    func writeData(_ data: Data, to name: String) throws {
        try data.write(to: url(for: name), options: [.atomic, .completeFileProtection])
    }

    func readData(from name: String) throws -> Data {
        try Data(contentsOf: url(for: name))
    }

    func exists(_ name: String) throws -> Bool {
        FileManager.default.fileExists(atPath: try url(for: name).path)
    }

    func delete(_ name: String) throws {
        let destination = try url(for: name)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
    }

    func deleteDirectory(_ name: String) throws {
        let destination = try url(for: name)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
    }

    func size(ofDirectory name: String) throws -> Int64 {
        let directory = try url(for: name)
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var bytes: Int64 = 0
        for case let fileURL as URL in enumerator {
            let values = try fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            if values.isRegularFile == true { bytes += Int64(values.fileSize ?? 0) }
        }
        return bytes
    }
}
