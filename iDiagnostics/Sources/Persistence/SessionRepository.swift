import Foundation

protocol SessionRepository {
    func load() throws -> DiagnosticSession?
    func save(_ session: DiagnosticSession) throws
    func remove() throws
}

enum SessionRepositoryError: LocalizedError {
    case unreadableSession
    case unsupportedSchema(Int)

    var errorDescription: String? {
        switch self {
        case .unreadableSession:
            return "تعذر قراءة جلسة الفحص السابقة، لذلك تم حفظها كنسخة تالفة وبدء جلسة سليمة."
        case .unsupportedSchema(let schema):
            return "إصدار بيانات الفحص (\(schema)) غير مدعوم في هذا الإصدار من التطبيق."
        }
    }
}

final class DiskSessionRepository: SessionRepository {
    private let fileManager: FileManager
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileManager: FileManager = .default, fileURL: URL? = nil) {
        self.fileManager = fileManager
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? fileManager.temporaryDirectory
            self.fileURL = base
                .appendingPathComponent("iDiagnostics", isDirectory: true)
                .appendingPathComponent("current-session-v2.json", isDirectory: false)
        }

        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func load() throws -> DiagnosticSession? {
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
        do {
            let data = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
            let session = try decoder.decode(DiagnosticSession.self, from: data)
            guard session.schema == DiagnosticSession.schemaVersion else {
                throw SessionRepositoryError.unsupportedSchema(session.schema)
            }
            return session
        } catch let error as SessionRepositoryError {
            try? quarantineCorruptFile()
            throw error
        } catch {
            try? quarantineCorruptFile()
            throw SessionRepositoryError.unreadableSession
        }
    }

    func save(_ session: DiagnosticSession) throws {
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try encoder.encode(session)
        try data.write(to: fileURL, options: [.atomic])
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = fileURL
        try? mutableURL.setResourceValues(values)
    }

    func remove() throws {
        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        try fileManager.removeItem(at: fileURL)
    }

    private func quarantineCorruptFile() throws {
        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        let stamp = Int(Date().timeIntervalSince1970)
        let quarantine = fileURL.deletingPathExtension()
            .appendingPathExtension("corrupt-\(stamp).json")
        try fileManager.moveItem(at: fileURL, to: quarantine)
    }
}

final class MemorySessionRepository: SessionRepository {
    var session: DiagnosticSession?

    init(session: DiagnosticSession? = nil) {
        self.session = session
    }

    func load() throws -> DiagnosticSession? { session }
    func save(_ session: DiagnosticSession) throws { self.session = session }
    func remove() throws { session = nil }
}
