import Foundation

@MainActor
final class BackupService {
    enum BackupError: LocalizedError {
        case unsupportedSchema(Int)
        case backupTooLarge
        case invalidBackup

        var errorDescription: String? {
            switch self {
            case let .unsupportedSchema(version): return "إصدار النسخة الاحتياطية \(version) غير مدعوم."
            case .backupTooLarge: return "ملف النسخة الاحتياطية أكبر من الحد الآمن البالغ 25 ميغابايت."
            case .invalidBackup: return "الملف لا يحتوي نسخة EnglishNova صالحة."
            }
        }
    }

    static let maximumBackupBytes = 25 * 1_024 * 1_024

    private let session: UserSession
    private let settings: AppSettings
    private let progressRepository: ProgressRepositoryProtocol
    private let vocabularyRepository: VocabularyRepositoryProtocol
    private let learningMemoryRepository: LearningMemoryRepositoryProtocol

    init(
        session: UserSession,
        settings: AppSettings,
        progressRepository: ProgressRepositoryProtocol,
        vocabularyRepository: VocabularyRepositoryProtocol,
        learningMemoryRepository: LearningMemoryRepositoryProtocol
    ) {
        self.session = session
        self.settings = settings
        self.progressRepository = progressRepository
        self.vocabularyRepository = vocabularyRepository
        self.learningMemoryRepository = learningMemoryRepository
    }

    func makeBackupData() async throws -> Data {
        async let progress = progressRepository.snapshot()
        async let vocabulary = vocabularyRepository.allCards()
        async let memory = learningMemoryRepository.snapshot()
        let backup = EnglishNovaBackup(
            schemaVersion: 4,
            appVersion: "1.0.0",
            exportedAt: .now,
            session: session.exportSnapshot(),
            settings: settings.exportSnapshot(),
            progress: await progress,
            vocabulary: await vocabulary,
            learningMemory: await memory
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(backup)
        guard data.count <= Self.maximumBackupBytes else { throw BackupError.backupTooLarge }
        return data
    }

    func makeTemporaryBackupFile() async throws -> URL {
        let data = try await makeBackupData()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        let name = "EnglishNova-Backup-\(formatter.string(from: .now)).json"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try data.write(to: url, options: .atomic)
        return url
    }

    func restore(from data: Data) async throws {
        guard data.count <= Self.maximumBackupBytes else { throw BackupError.backupTooLarge }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let backup = try? decoder.decode(EnglishNovaBackup.self, from: data) else {
            throw BackupError.invalidBackup
        }
        guard (1...4).contains(backup.schemaVersion) else { throw BackupError.unsupportedSchema(backup.schemaVersion) }
        guard backup.vocabulary.count <= 100_000,
              backup.progress.practiceSessions.count <= 1_000,
              backup.progress.knowledgeStates.count <= 5_000 else { throw BackupError.invalidBackup }
        if let memory = backup.learningMemory {
            guard memory.mistakes.count <= 1_000,
                  memory.pronunciationReports.count <= 300,
                  memory.conversations.count <= 250 else {
                throw BackupError.invalidBackup
            }
        }
        await session.importSnapshot(backup.session)
        await settings.importSnapshot(backup.settings)
        await progressRepository.replace(with: backup.progress)
        await vocabularyRepository.replace(with: backup.vocabulary)
        if let memory = backup.learningMemory {
            await learningMemoryRepository.replace(with: memory)
        }
    }
}
