import Foundation

struct RemoteTutorClient {
    let apiClient: APIClient

    private struct TutorBody: Encodable {
        let message: String
        let level: String
    }

    func reply(request: TutorRequest) async throws -> TutorResponse {
        // Talks to the server AI tutor (/ai/tutor), authenticated with the
        // signed-in user's token. The token lives in the Keychain (same item
        // AccountService writes), read here directly to avoid actor hops.
        let token = KeychainStore().string(for: "server.authToken")
        return try await apiClient.send(
            path: "ai/tutor",
            method: "POST",
            body: TutorBody(message: request.message, level: request.level),
            response: TutorResponse.self,
            bearerToken: token
        )
    }
}

struct RemoteVoiceCoachClient {
    let apiClient: APIClient

    func reply(request: VoiceCoachRequest) async throws -> VoiceCoachReply {
        try await apiClient.send(
            path: "v1/coach/conversation",
            method: "POST",
            body: request,
            response: VoiceCoachReply.self
        )
    }
}
