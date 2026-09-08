import Foundation

struct LocalTutorEngine {
    func reply(to message: String, level: CEFRLevel) -> TutorMessage {
        let clean = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = clean.lowercased()
        var corrections: [TutorCorrection] = []
        var reply: String
        var suggestions: [String]

        if clean.isEmpty {
            reply = "اكتب جملة أو سؤالًا قصيرًا، وسأساعدك في تحسينه."
            suggestions = ["Can you give me an example?", "Let's practise English."]
        } else if containsArabic(clean) {
            reply = arabicFallbackReply(for: clean, level: level)
            suggestions = ["Who are you?", "Can you help me practise English?"]
        } else if lower.contains("i am agree") {
            corrections.append(.init(original: "I am agree", replacement: "I agree", reason: "agree فعل ولا يحتاج am"))
            reply = "الصحيح: I agree. بعد أن تضبط الجملة، يمكنك توسيعها بسبب بسيط مثل: I agree because it is useful."
            suggestions = ["Why is this correct?", "Can you give me another example?"]
        } else if lower.contains("i go") && lower.contains("yesterday") {
            corrections.append(.init(original: "go", replacement: "went", reason: "نستخدم الماضي went مع yesterday"))
            reply = "ممتاز أنك حدّدت الزمن. الصياغة الصحيحة هنا: I went yesterday."
            suggestions = ["Can you explain the past tense?", "Give me another past-tense example."]
        } else if clean.hasSuffix("?") || startsLikeQuestion(lower) {
            reply = "أنا المدرّب المحلي الاحتياطي في EnglishNova. الاتصال بالخادم يعطيك تدريبًا أذكى، أما هنا فأستطيع مساعدتك في تصحيح الجمل الإنجليزية الشائعة ومواصلة تدريب قصير على مستوى \(level.rawValue)."
            suggestions = ["Can you correct this sentence?", "Give me a short practice question."]
        } else {
            reply = levelAwareFallback(for: clean, level: level)
            suggestions = ["Can you correct my sentence?", "How can I make this more natural?"]
        }

        return TutorMessage(
            role: .assistant,
            text: reply,
            corrections: corrections,
            suggestedReplies: suggestions
        )
    }

    private func containsArabic(_ value: String) -> Bool {
        value.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x0600...0x06FF, 0x0750...0x077F, 0x08A0...0x08FF:
                return true
            default:
                return false
            }
        }
    }

    private func arabicFallbackReply(for message: String, level: CEFRLevel) -> String {
        let normalized = message
            .replacingOccurrences(of: "؟", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if normalized.contains("من انت") || normalized.contains("من أنت") || normalized.contains("مين انت") || normalized.contains("مين أنت") {
            return "أنا المدرّب المحلي الاحتياطي في EnglishNova. أعمل داخل الجهاز عندما لا تصل خدمة المدرّب عبر الإنترنت. أستطيع مساعدتك في تدريب قصير وتصحيح بعض الأخطاء الشائعة، لكن الردود المتقدمة تأتي من المدرّب الذكي عند توفر الاتصال."
        }

        return "فهمت رسالتك العربية. المدرّب المحلي لا يحوّل النص العربي إلى جملة إنجليزية عشوائيًا. إذا أردت التعلّم، اكتب الجملة الإنجليزية التي تريد تصحيحها، أو اطلب تمرينًا قصيرًا مناسبًا لمستوى \(level.rawValue)."
    }

    private func startsLikeQuestion(_ lower: String) -> Bool {
        let starters = ["who ", "what ", "where ", "when ", "why ", "how ", "can ", "could ", "do ", "does ", "did ", "is ", "are ", "am ", "will ", "would ", "should "]
        return starters.contains { lower.hasPrefix($0) }
    }

    private func levelAwareFallback(for sentence: String, level: CEFRLevel) -> String {
        switch level {
        case .a0, .a1:
            return "وصلتني الجملة: “\(sentence)”. في الوضع المحلي سأركز على جملة قصيرة صحيحة بدل اختراع تتمة لها. راجع ترتيب الفاعل ثم الفعل ثم بقية المعنى، أو اطلب مني تصحيح جملة محددة."
        case .a2:
            return "وصلتني الجملة: “\(sentence)”. اجعلها أوضح بإضافة معلومة واحدة فقط، مثل الزمن أو المكان أو السبب، لكن لا تضف كلمات لا تخدم المعنى الذي تقصده."
        case .b1, .b2, .c1:
            return "وصلتني الجملة: “\(sentence)”. في الوضع المحلي أستطيع إعطاء ملاحظة عامة فقط. طوّر الفكرة بتفصيل مرتبط بالمعنى، ثم راجع الدقة والترابط. للحصول على تحليل لغوي كامل استخدم المدرّب عبر الإنترنت."
        }
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
