import Foundation

/// Which engine answers in the interactive tutor.
enum TutorProvider: String, Codable, CaseIterable, Identifiable {
    case smart
    case device
    /// Legacy value kept only so older settings continue to decode. The UI
    /// migrates it to `.smart` because personal Gemini keys are no longer used.
    case gemini

    var id: String { rawValue }

    var titleAr: String {
        switch self {
        case .smart: return L("تلقائي")
        case .device: return L("على الجهاز فقط")
        case .gemini: return L("تلقائي")
        }
    }

    var detailAr: String {
        switch self {
        case .smart, .gemini:
            return L("يستخدم المدرّب عبر الإنترنت عندما تكون الخدمة متاحة، ويرجع إلى المدرّب المحلي عند تعذر الاتصال.")
        case .device:
            return L("يبقي المحادثة داخل الجهاز ولا يستخدم خدمة المدرّب عبر الإنترنت.")
        }
    }
}

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
    var corrections: [TutorCorrection] = []
    var suggestedReplies: [String] = []

    init(reply: String, corrections: [TutorCorrection] = [], suggestedReplies: [String] = []) {
        self.reply = reply
        self.corrections = corrections
        self.suggestedReplies = suggestedReplies
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        reply = try container.decodeIfPresent(String.self, forKey: .reply) ?? ""
        corrections = try container.decodeIfPresent([TutorCorrection].self, forKey: .corrections) ?? []
        suggestedReplies = try container.decodeIfPresent([String].self, forKey: .suggestedReplies) ?? []
    }
}

struct TutorConversation: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var createdAt: Date = .now
    var updatedAt: Date = .now
    var provider: TutorProvider = .smart
    var messages: [TutorMessage] = []

    var title: String {
        if let firstUser = messages.first(where: { $0.role == .user })?.text
            .trimmingCharacters(in: .whitespacesAndNewlines), !firstUser.isEmpty {
            return String(firstUser.prefix(60))
        }
        return L("محادثة جديدة")
    }

    var hasLearnerContent: Bool {
        messages.contains {
            $0.role == .user && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
}
