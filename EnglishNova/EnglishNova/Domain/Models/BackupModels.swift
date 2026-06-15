import Foundation

struct EnglishNovaBackup: Codable {
    let schemaVersion: Int
    let appVersion: String
    let exportedAt: Date
    let session: SessionSnapshot
    let settings: SettingsSnapshot
    let progress: UserProgressSnapshot
    let vocabulary: [ReviewCard]
    let learningMemory: LearnerMemorySnapshot?

    enum CodingKeys: String, CodingKey {
        case schemaVersion, appVersion, exportedAt, session, settings, progress, vocabulary, learningMemory
    }

    init(
        schemaVersion: Int,
        appVersion: String,
        exportedAt: Date,
        session: SessionSnapshot,
        settings: SettingsSnapshot,
        progress: UserProgressSnapshot,
        vocabulary: [ReviewCard],
        learningMemory: LearnerMemorySnapshot?
    ) {
        self.schemaVersion = schemaVersion
        self.appVersion = appVersion
        self.exportedAt = exportedAt
        self.session = session
        self.settings = settings
        self.progress = progress
        self.vocabulary = vocabulary
        self.learningMemory = learningMemory
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        appVersion = try container.decode(String.self, forKey: .appVersion)
        exportedAt = try container.decode(Date.self, forKey: .exportedAt)
        session = try container.decode(SessionSnapshot.self, forKey: .session)
        settings = try container.decode(SettingsSnapshot.self, forKey: .settings)
        progress = try container.decode(UserProgressSnapshot.self, forKey: .progress)
        vocabulary = try container.decodeIfPresent([ReviewCard].self, forKey: .vocabulary) ?? []
        learningMemory = try container.decodeIfPresent(LearnerMemorySnapshot.self, forKey: .learningMemory)
    }
}
