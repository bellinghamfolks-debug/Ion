import Foundation

struct TutorMessage: Codable, Identifiable, Hashable {
    enum Role: String, Codable { case user, assistant, system }
    var id: UUID = UUID()
    var role: Role
    var text: String
    var createdAt: Date = .now
    var corrections: [TutorCorrection] = []
    var suggestedReplies: [String] = []
}

struct TutorCorrection: Codable, Hashable {
    var original: String
    var replacement: String
    var reason: String
}

struct TutorRequest: Codable {
    var sessionId: String
    var locale: String
    var level: String
    var message: String
    var context: String?
}

struct TutorResponse: Codable {
    var reply: String
    var corrections: [TutorCorrection]
    var suggestedReplies: [String]
}
