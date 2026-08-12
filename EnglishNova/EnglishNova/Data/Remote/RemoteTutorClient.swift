import Foundation

struct RemoteTutorClient {
    let apiClient: APIClient

    private struct TutorBody: Encodable {
        let message: String
        let level: String
        let sessionId: String
        let locale: String
        let context: String?
    }

    func reply(request: TutorRequest) async throws -> TutorResponse {
        // Send the full teaching context. The server combines this recent local
        // context with the synced learner profile instead of treating every
        // message as a brand-new conversation.
        let token = KeychainStore().string(for: "server.authToken")
        return try await apiClient.send(
            path: "ai/tutor",
            method: "POST",
            body: TutorBody(
                message: request.message,
                level: request.level,
                sessionId: request.sessionId,
                locale: request.locale,
                context: request.context
            ),
            response: TutorResponse.self,
            bearerToken: token
        )
    }
}

struct RemoteVoiceCoachClient {
    let apiClient: APIClient

    private struct PreviousTurn: Encodable {
        let transcript: String
        let reply: String
        let score: Double
    }

    private struct CoachBody: Encodable {
        let prompt: String
        let transcript: String
        let level: String
        let scenarioId: String
        let accent: String
        let localScore: Double
        let previousTurns: [PreviousTurn]
    }

    func reply(request: VoiceCoachRequest) async throws -> VoiceCoachReply {
        // Preserve the rich context already computed on-device. iOS remains the
        // source of truth for speech-recognition metrics; the server AI uses
        // those metrics plus conversation history for semantic coaching.
        let token = KeychainStore().string(for: "server.authToken")
        let history = request.previousTurns.prefix(6).map {
            PreviousTurn(transcript: $0.transcript, reply: $0.reply, score: $0.score)
        }
        return try await apiClient.send(
            path: "ai/coach",
            method: "POST",
            body: CoachBody(
                prompt: request.prompt,
                transcript: request.learnerTranscript,
                level: request.level.rawValue,
                scenarioId: request.scenarioID,
                accent: request.accent.rawValue,
                localScore: request.localScore,
                previousTurns: Array(history)
            ),
            response: VoiceCoachReply.self,
            bearerToken: token
        )
    }
}
