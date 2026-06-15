import Foundation

struct RemoteTutorClient {
    let apiClient: APIClient

    func reply(request: TutorRequest) async throws -> TutorResponse {
        try await apiClient.send(path: "v1/tutor/message", method: "POST", body: request, response: TutorResponse.self)
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
