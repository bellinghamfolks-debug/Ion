import Foundation
import Combine

struct SettingsSnapshot: Codable {
    var interfaceLanguage: AppSettings.InterfaceLanguage
    var dailyGoalMinutes: Int
    var speechRate: Double
    var hapticsEnabled: Bool
    var serverURLString: String
    var reminderEnabled: Bool
    var reminderHour: Int
    var reminderMinute: Int
    var autoPlayLessonAudio: Bool
    var reduceLearningPressure: Bool
    var accentVariant: AccentVariant
    var adaptiveCoachEnabled: Bool
    var autoSpeakCoachPrompts: Bool
    var showArabicCoachHints: Bool
    var studyMode: StudyMode
    var selectedLearningPathway: LearningPathwayID
    var weeklyTargetDays: Int
    var revealListeningTranscriptAfterAnswer: Bool

    enum CodingKeys: String, CodingKey {
        case interfaceLanguage, dailyGoalMinutes, speechRate, hapticsEnabled, serverURLString
        case reminderEnabled, reminderHour, reminderMinute, autoPlayLessonAudio, reduceLearningPressure
        case accentVariant, adaptiveCoachEnabled, autoSpeakCoachPrompts, showArabicCoachHints
        case studyMode, selectedLearningPathway, weeklyTargetDays, revealListeningTranscriptAfterAnswer
    }

    init(
        interfaceLanguage: AppSettings.InterfaceLanguage,
        dailyGoalMinutes: Int,
        speechRate: Double,
        hapticsEnabled: Bool,
        serverURLString: String,
        reminderEnabled: Bool,
        reminderHour: Int,
        reminderMinute: Int,
        autoPlayLessonAudio: Bool,
        reduceLearningPressure: Bool,
        accentVariant: AccentVariant,
        adaptiveCoachEnabled: Bool,
        autoSpeakCoachPrompts: Bool,
        showArabicCoachHints: Bool,
        studyMode: StudyMode,
        selectedLearningPathway: LearningPathwayID,
        weeklyTargetDays: Int,
        revealListeningTranscriptAfterAnswer: Bool
    ) {
        self.interfaceLanguage = interfaceLanguage
        self.dailyGoalMinutes = dailyGoalMinutes
        self.speechRate = speechRate
        self.hapticsEnabled = hapticsEnabled
        self.serverURLString = serverURLString
        self.reminderEnabled = reminderEnabled
        self.reminderHour = reminderHour
        self.reminderMinute = reminderMinute
        self.autoPlayLessonAudio = autoPlayLessonAudio
        self.reduceLearningPressure = reduceLearningPressure
        self.accentVariant = accentVariant
        self.adaptiveCoachEnabled = adaptiveCoachEnabled
        self.autoSpeakCoachPrompts = autoSpeakCoachPrompts
        self.showArabicCoachHints = showArabicCoachHints
        self.studyMode = studyMode
        self.selectedLearningPathway = selectedLearningPathway
        self.weeklyTargetDays = weeklyTargetDays
        self.revealListeningTranscriptAfterAnswer = revealListeningTranscriptAfterAnswer
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        interfaceLanguage = try container.decodeIfPresent(AppSettings.InterfaceLanguage.self, forKey: .interfaceLanguage) ?? .arabic
        dailyGoalMinutes = try container.decodeIfPresent(Int.self, forKey: .dailyGoalMinutes) ?? 15
        speechRate = try container.decodeIfPresent(Double.self, forKey: .speechRate) ?? 0.45
        hapticsEnabled = try container.decodeIfPresent(Bool.self, forKey: .hapticsEnabled) ?? true
        serverURLString = try container.decodeIfPresent(String.self, forKey: .serverURLString) ?? ""
        reminderEnabled = try container.decodeIfPresent(Bool.self, forKey: .reminderEnabled) ?? false
        reminderHour = try container.decodeIfPresent(Int.self, forKey: .reminderHour) ?? 19
        reminderMinute = try container.decodeIfPresent(Int.self, forKey: .reminderMinute) ?? 0
        autoPlayLessonAudio = try container.decodeIfPresent(Bool.self, forKey: .autoPlayLessonAudio) ?? false
        reduceLearningPressure = try container.decodeIfPresent(Bool.self, forKey: .reduceLearningPressure) ?? false
        accentVariant = try container.decodeIfPresent(AccentVariant.self, forKey: .accentVariant) ?? .american
        adaptiveCoachEnabled = try container.decodeIfPresent(Bool.self, forKey: .adaptiveCoachEnabled) ?? true
        autoSpeakCoachPrompts = try container.decodeIfPresent(Bool.self, forKey: .autoSpeakCoachPrompts) ?? true
        showArabicCoachHints = try container.decodeIfPresent(Bool.self, forKey: .showArabicCoachHints) ?? true
        studyMode = try container.decodeIfPresent(StudyMode.self, forKey: .studyMode) ?? .balanced
        selectedLearningPathway = try container.decodeIfPresent(LearningPathwayID.self, forKey: .selectedLearningPathway) ?? .foundations
        weeklyTargetDays = min(7, max(2, try container.decodeIfPresent(Int.self, forKey: .weeklyTargetDays) ?? 5))
        revealListeningTranscriptAfterAnswer = try container.decodeIfPresent(Bool.self, forKey: .revealListeningTranscriptAfterAnswer) ?? true
    }
}

@MainActor
final class AppSettings: ObservableObject {
    enum InterfaceLanguage: String, Codable, CaseIterable, Identifiable {
        case arabic = "ar"
        case english = "en"
        var id: String { rawValue }
        var title: String { self == .arabic ? "العربية" : "English" }
    }

    @Published var interfaceLanguage: InterfaceLanguage = .arabic { didSet { persist() } }
    @Published var dailyGoalMinutes: Int = 15 { didSet { persist() } }
    @Published var speechRate: Double = 0.45 { didSet { persist() } }
    @Published var hapticsEnabled: Bool = true { didSet { persist() } }
    @Published var serverURLString: String = UserDefaults.standard.string(forKey: ServerEndpoint.defaultsKey) ?? "" { didSet { ServerEndpoint.save(serverURLString); persist() } }
    @Published var reminderEnabled = false { didSet { persist() } }
    @Published var reminderHour = 19 { didSet { persist() } }
    @Published var reminderMinute = 0 { didSet { persist() } }
    @Published var autoPlayLessonAudio = false { didSet { persist() } }
    @Published var reduceLearningPressure = false { didSet { persist() } }
    @Published var accentVariant: AccentVariant = .american { didSet { persist() } }
    @Published var adaptiveCoachEnabled = true { didSet { persist() } }
    @Published var autoSpeakCoachPrompts = true { didSet { persist() } }
    @Published var showArabicCoachHints = true { didSet { persist() } }
    @Published var studyMode: StudyMode = .balanced { didSet { persist() } }
    @Published var selectedLearningPathway: LearningPathwayID = .foundations { didSet { persist() } }
    @Published var weeklyTargetDays = 5 { didSet { persist() } }
    @Published var revealListeningTranscriptAfterAnswer = true { didSet { persist() } }

    private let store: FileStore
    private let key = "settings.json"
    private var isLoading = false

    init(store: FileStore) {
        self.store = store
        Task { await load() }
    }

    var serverURL: URL? { URL(string: serverURLString.trimmingCharacters(in: .whitespacesAndNewlines)) }

    var reminderDate: Date {
        Calendar.current.date(from: DateComponents(hour: reminderHour, minute: reminderMinute)) ?? .now
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        guard let snapshot: SettingsSnapshot = try? await store.read(SettingsSnapshot.self, from: key) else { return }
        apply(snapshot)
    }

    func exportSnapshot() -> SettingsSnapshot {
        SettingsSnapshot(
            interfaceLanguage: interfaceLanguage,
            dailyGoalMinutes: dailyGoalMinutes,
            speechRate: speechRate,
            hapticsEnabled: hapticsEnabled,
            serverURLString: serverURLString,
            reminderEnabled: reminderEnabled,
            reminderHour: reminderHour,
            reminderMinute: reminderMinute,
            autoPlayLessonAudio: autoPlayLessonAudio,
            reduceLearningPressure: reduceLearningPressure,
            accentVariant: accentVariant,
            adaptiveCoachEnabled: adaptiveCoachEnabled,
            autoSpeakCoachPrompts: autoSpeakCoachPrompts,
            showArabicCoachHints: showArabicCoachHints,
            studyMode: studyMode,
            selectedLearningPathway: selectedLearningPathway,
            weeklyTargetDays: weeklyTargetDays,
            revealListeningTranscriptAfterAnswer: revealListeningTranscriptAfterAnswer
        )
    }

    func importSnapshot(_ snapshot: SettingsSnapshot) async {
        isLoading = true
        apply(snapshot)
        isLoading = false
        persist()
    }

    private func apply(_ snapshot: SettingsSnapshot) {
        interfaceLanguage = snapshot.interfaceLanguage
        dailyGoalMinutes = min(120, max(5, snapshot.dailyGoalMinutes))
        speechRate = min(0.58, max(0.30, snapshot.speechRate))
        hapticsEnabled = snapshot.hapticsEnabled
        serverURLString = Self.sanitizedServerURL(snapshot.serverURLString)
        reminderEnabled = snapshot.reminderEnabled
        reminderHour = min(23, max(0, snapshot.reminderHour))
        reminderMinute = min(59, max(0, snapshot.reminderMinute))
        autoPlayLessonAudio = snapshot.autoPlayLessonAudio
        reduceLearningPressure = snapshot.reduceLearningPressure
        accentVariant = snapshot.accentVariant
        adaptiveCoachEnabled = snapshot.adaptiveCoachEnabled
        autoSpeakCoachPrompts = snapshot.autoSpeakCoachPrompts
        showArabicCoachHints = snapshot.showArabicCoachHints
        studyMode = snapshot.studyMode
        selectedLearningPathway = snapshot.selectedLearningPathway
        weeklyTargetDays = min(7, max(2, snapshot.weeklyTargetDays))
        revealListeningTranscriptAfterAnswer = snapshot.revealListeningTranscriptAfterAnswer
    }

    private static func sanitizedServerURL(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        guard let url = URL(string: trimmed), url.scheme?.lowercased() == "https", url.host != nil else { return "" }
        return trimmed
    }

    private func persist() {
        guard !isLoading else { return }
        let snapshot = exportSnapshot()
        Task { try? await store.write(snapshot, to: key) }
    }
}
