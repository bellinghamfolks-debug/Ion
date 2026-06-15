import Foundation

struct LocalTutorEngine {
    func reply(to message: String, level: CEFRLevel) -> TutorMessage {
        let clean = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = clean.lowercased()
        var corrections: [TutorCorrection] = []
        var reply: String

        if lower.contains("i am agree") {
            corrections.append(.init(original: "I am agree", replacement: "I agree", reason: "agree فعل ولا يحتاج am"))
            reply = "الصحيح: I agree. جرّب أن تضيف السبب، مثل: I agree because it is useful."
        } else if lower.contains("i go") && lower.contains("yesterday") {
            corrections.append(.init(original: "go", replacement: "went", reason: "نستخدم الماضي went مع yesterday"))
            reply = "ممتاز أنك حدّدت الزمن. قل: I went yesterday."
        } else if clean.isEmpty {
            reply = "اكتب جملة إنجليزية قصيرة، وسأساعدك في تحسينها."
        } else {
            reply = "جملتك مفهومة. لنطوّرها خطوة إضافية: أضف متى حدث الأمر أو لماذا. مثال: \(clean) because it was important."
        }
        return TutorMessage(role: .assistant, text: reply, corrections: corrections, suggestedReplies: ["Can you give me another example?", "Why is this correct?"])
    }
}

struct LocalVoiceCoachEngine {
    func reply(to request: VoiceCoachRequest) -> VoiceCoachReply {
        let normalized = request.learnerTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        let encouragement: String
        if request.localScore >= 0.82 {
            encouragement = "ردك مناسب وواضح. حافظ على هذا الإيقاع وأضف تفصيلًا صغيرًا عندما يكون الموقف رسميًا."
        } else if request.localScore >= 0.58 {
            encouragement = "المعنى وصل، لكن يمكن جعل الرد أدق بإضافة الفكرة الأساسية بعبارة قصيرة مباشرة."
        } else {
            encouragement = "ابدأ بجملة أقصر، ثم أضف سببًا واحدًا. لا تحاول بناء إجابة طويلة من المحاولة الأولى."
        }

        let reply: String
        if normalized.isEmpty {
            reply = "Take your time. Start with one short sentence."
        } else if normalized.lowercased().contains("thank") {
            reply = "You’re welcome. Could you tell me one more detail?"
        } else if normalized.lowercased().contains("because") {
            reply = "That makes sense. Can you give me a short example?"
        } else {
            reply = "I understand. What is the main reason for that?"
        }

        return VoiceCoachReply(
            reply: reply,
            translationAr: "أفهم. ما السبب الرئيسي لذلك؟",
            feedbackAr: encouragement,
            suggestedAnswer: request.localScore < 0.58 ? "I think this is important because it helps people." : nil,
            source: "local"
        )
    }
}
