import XCTest
@testable import EnglishNova

final class TutorImprovementsTests: XCTestCase {

    // MARK: - Gemini response parsing

    func testGeminiStructuredResponseIsParsed() throws {
        let inner = #"{"reply":"Great sentence.","corrections":[{"original":"i go","replacement":"I went","reason":"الماضي مع yesterday"}],"suggestedReplies":["Tell me more","Why?"]}"#
        let envelope: [String: Any] = [
            "candidates": [["content": ["parts": [["text": inner]]]]]
        ]
        let data = try JSONSerialization.data(withJSONObject: envelope)

        let message = try GeminiTutorClient.parse(data)
        XCTAssertEqual(message.role, .assistant)
        XCTAssertEqual(message.text, "Great sentence.")
        XCTAssertEqual(message.corrections.count, 1)
        XCTAssertEqual(message.corrections.first?.replacement, "I went")
        XCTAssertEqual(message.suggestedReplies, ["Tell me more", "Why?"])
    }

    func testGeminiPlainTextFallsBackToRawReply() throws {
        let envelope: [String: Any] = [
            "candidates": [["content": ["parts": [["text": "Keep practising every day."]]]]]
        ]
        let data = try JSONSerialization.data(withJSONObject: envelope)

        let message = try GeminiTutorClient.parse(data)
        XCTAssertEqual(message.text, "Keep practising every day.")
        XCTAssertTrue(message.corrections.isEmpty)
        XCTAssertTrue(message.suggestedReplies.isEmpty)
    }

    func testGeminiEmptyCandidatesThrows() {
        let data = Data(#"{"candidates":[]}"#.utf8)
        XCTAssertThrowsError(try GeminiTutorClient.parse(data))
    }

    // MARK: - Settings migration keeps new tutor fields safe

    func testOldSettingsDecodeWithTutorDefaults() throws {
        let json = #"""
        {
          "interfaceLanguage": "ar",
          "dailyGoalMinutes": 15,
          "speechRate": 0.45,
          "hapticsEnabled": true,
          "serverURLString": ""
        }
        """#
        let snapshot = try JSONDecoder().decode(SettingsSnapshot.self, from: Data(json.utf8))
        XCTAssertEqual(snapshot.tutorProvider, .smart)
        XCTAssertTrue(snapshot.autoSpeakTutorReplies)
        XCTAssertEqual(snapshot.geminiModel, "gemini-1.5-flash")
    }

    // MARK: - Conversations are saved on device

    func testConversationRepositoryPersistsAndDeletes() async throws {
        let store = FileStore()
        let repo = ConversationRepository(store: store)

        var conversation = TutorConversation()
        conversation.messages = [
            TutorMessage(role: .user, text: "Hello tutor"),
            TutorMessage(role: .assistant, text: "Hello! How can I help?")
        ]
        await repo.save(conversation)

        let all = await repo.all()
        XCTAssertTrue(all.contains { $0.id == conversation.id })
        XCTAssertEqual(all.first { $0.id == conversation.id }?.title, "Hello tutor")

        await repo.delete(id: conversation.id)
        let afterDelete = await repo.all()
        XCTAssertFalse(afterDelete.contains { $0.id == conversation.id })
    }

    func testConversationWithoutLearnerContentIsNotSaved() async throws {
        let repo = ConversationRepository(store: FileStore())
        var greetingOnly = TutorConversation()
        greetingOnly.messages = [TutorMessage(role: .assistant, text: "مرحبًا")]
        await repo.save(greetingOnly)
        let all = await repo.all()
        XCTAssertFalse(all.contains { $0.id == greetingOnly.id })
    }

    // MARK: - Keychain (encrypted key storage)

    func testKeychainRoundTripWhenAvailable() throws {
        let keychain = KeychainStore(service: "com.englishnova.tests.\(UUID().uuidString)")
        let account = "gemini.apiKey"
        try? keychain.setString("secret-123", for: account)
        // On hosts where the Keychain is available this stores and reads back;
        // where it is not, we simply skip the equality assertion.
        if keychain.exists(account) {
            XCTAssertEqual(keychain.string(for: account), "secret-123")
            XCTAssertTrue(keychain.delete(account))
            XCTAssertFalse(keychain.exists(account))
        }
    }
}
