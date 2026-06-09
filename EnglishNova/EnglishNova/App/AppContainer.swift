import Foundation
import Combine

@MainActor
final class AppContainer: ObservableObject {
    let settings: AppSettings
    let session: UserSession
    let courseRepository: CourseRepositoryProtocol
    let progressRepository: ProgressRepositoryProtocol
    let vocabularyRepository: VocabularyRepositoryProtocol
    let learningMemoryRepository: LearningMemoryRepositoryProtocol
    let tutorRepository: TutorRepositoryProtocol
    let conversationRepository: ConversationRepositoryProtocol
    let voiceCoachRepository: VoiceCoachRepositoryProtocol
    let speechService: SpeechService
    let textToSpeech: TextToSpeechService
    let networkMonitor: NetworkMonitor
    let contentUpdateService: ContentUpdateService
    let audioPackService: AudioPackService
    let reminderService: StudyReminderService
    let backupService: BackupService

    init(
        settings: AppSettings,
        session: UserSession,
        courseRepository: CourseRepositoryProtocol,
        progressRepository: ProgressRepositoryProtocol,
        vocabularyRepository: VocabularyRepositoryProtocol,
        learningMemoryRepository: LearningMemoryRepositoryProtocol,
        tutorRepository: TutorRepositoryProtocol,
        conversationRepository: ConversationRepositoryProtocol,
        voiceCoachRepository: VoiceCoachRepositoryProtocol,
        speechService: SpeechService,
        textToSpeech: TextToSpeechService,
        networkMonitor: NetworkMonitor,
        contentUpdateService: ContentUpdateService,
        audioPackService: AudioPackService,
        reminderService: StudyReminderService,
        backupService: BackupService
    ) {
        self.settings = settings
        self.session = session
        self.courseRepository = courseRepository
        self.progressRepository = progressRepository
        self.vocabularyRepository = vocabularyRepository
        self.learningMemoryRepository = learningMemoryRepository
        self.tutorRepository = tutorRepository
        self.conversationRepository = conversationRepository
        self.voiceCoachRepository = voiceCoachRepository
        self.speechService = speechService
        self.textToSpeech = textToSpeech
        self.networkMonitor = networkMonitor
        self.contentUpdateService = contentUpdateService
        self.audioPackService = audioPackService
        self.reminderService = reminderService
        self.backupService = backupService
    }

    static func live() -> AppContainer {
        let store = FileStore()
        let settings = AppSettings(store: store)
        let session = UserSession(store: store)
        let progress = ProgressRepository(store: store)
        let vocabulary = VocabularyRepository(store: store)
        let memory = LearningMemoryRepository(store: store)
        let client = APIClient(configuration: .init(baseURL: settings.serverURL))
        let speech = SpeechService()
        let textToSpeech = TextToSpeechService()
        return AppContainer(
            settings: settings,
            session: session,
            courseRepository: CourseRepository(loader: BundledContentLoader()),
            progressRepository: progress,
            vocabularyRepository: vocabulary,
            learningMemoryRepository: memory,
            tutorRepository: RoutingTutorRepository(
                gemini: GeminiTutorClient(),
                remote: RemoteTutorClient(apiClient: client),
                local: LocalTutorEngine(),
                settings: settings
            ),
            conversationRepository: ConversationRepository(store: store),
            voiceCoachRepository: HybridVoiceCoachRepository(
                remote: RemoteVoiceCoachClient(apiClient: client),
                local: LocalVoiceCoachEngine()
            ),
            speechService: speech,
            textToSpeech: textToSpeech,
            networkMonitor: NetworkMonitor(),
            contentUpdateService: ContentUpdateService(apiClient: client),
            audioPackService: AudioPackService(apiClient: client, store: store),
            reminderService: StudyReminderService(),
            backupService: BackupService(
                session: session,
                settings: settings,
                progressRepository: progress,
                vocabularyRepository: vocabulary,
                learningMemoryRepository: memory
            )
        )
    }
}
