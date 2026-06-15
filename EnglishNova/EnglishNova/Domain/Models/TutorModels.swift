import Foundation

/// Which engine answers in the interactive tutor.
enum TutorProvider: String, Codable, CaseIterable, Identifiable {
    /// Use the configured app server when set, otherwise the on-device engine.
    case smart
    /// Always answer fully on-device (no network).
    case device
    /// Use Google's Gemini API with the user's own key (stored encrypted).
    case gemini

    var id: String { rawValue }

    var titleAr: String {
        switch self {
        case .smart: return "تلقائي (الخادم أو المحلي)"
        case .device: return "محلي على الجهاز"
        case .gemini: return "Gemini API (مفتاحك الخاص)"
        }
    }

    var detailAr: String {
        switch self {
        case .smart: return "يستخدم خادم التطبيق إن عُيّن، وإلا فالمدرّس المحلي. لا يحتاج مفتاحًا."
        case .device: return "يعمل دون إنترنت بالكامل ولا يرسل أي نص خارج الجهاز."
        case .gemini: return "يرسل رسالتك إلى Gemini باستخدام مفتاحك المحفوظ مشفّرًا على الجهاز."
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

/// A full tutor chat saved on the device so the learner can revisit it.
struct TutorConversation: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var createdAt: Date = .now
    var updatedAt: Date = .now
    var provider: TutorProvider = .smart
    var messages: [TutorMessage] = []

    /// A human-readable title derived from the first learner message.
    var title: String {
        if let firstUser = messages.first(where: { $0.role == .user })?.text
            .trimmingCharacters(in: .whitespacesAndNewlines), !firstUser.isEmpty {
            return String(firstUser.prefix(60))
        }
        return "محادثة جديدة"
    }

    /// True once the learner has actually said something worth keeping.
    var hasLearnerContent: Bool {
        messages.contains { $0.role == .user && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}
