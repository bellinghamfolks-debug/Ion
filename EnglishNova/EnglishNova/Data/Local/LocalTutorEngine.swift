import Foundation

struct LocalTutorEngine {
    func reply(to message: String, level: CEFRLevel) -> TutorMessage {
        let clean = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = clean.lowercased()
        var corrections: [TutorCorrection] = []
        var reply: String
        var suggestions: [String]

        if clean.isEmpty {
            reply = LE(
                "اكتب جملة أو سؤالًا قصيرًا، وسأساعدك في تحسينه.",
                "Write a short sentence or question and I’ll help you improve it."
            )
            suggestions = ["Can you give me an example?", "Let's practise English."]
        } else if containsArabic(clean) {
            reply = arabicFallbackReply(for: clean, level: level)
            suggestions = ["Who are you?", "Can you help me practise English?"]
        } else if lower.contains("i am agree") {
            corrections.append(.init(
                original: "I am agree",
                replacement: "I agree",
                reason: LE("agree فعل ولا يحتاج am", "agree is a verb and does not need am")
            ))
            reply = LE(
                "الصحيح: I agree. بعد أن تضبط الجملة، يمكنك توسيعها بسبب بسيط مثل: I agree because it is useful.",
                "The correct form is: I agree. Once the sentence is correct, you can extend it with a simple reason, for example: I agree because it is useful."
            )
            suggestions = ["Why is this correct?", "Can you give me another example?"]
        } else if lower.contains("i go") && lower.contains("yesterday") {
            corrections.append(.init(
                original: "go",
                replacement: "went",
                reason: LE("نستخدم الماضي went مع yesterday", "Use the past form went with yesterday")
            ))
            reply = LE(
                "ممتاز أنك حدّدت الزمن. الصياغة الصحيحة هنا: I went yesterday.",
                "Good job specifying the time. The correct form here is: I went yesterday."
            )
            suggestions = ["Can you explain the past tense?", "Give me another past-tense example."]
        } else if clean.hasSuffix("?") || startsLikeQuestion(lower) {
            reply = LfE(
                "أنا المدرّب المحلي الاحتياطي في EnglishNova. الاتصال بالخادم يعطيك تدريبًا أذكى، أما هنا فأستطيع مساعدتك في تصحيح الجمل الإنجليزية الشائعة ومواصلة تدريب قصير على مستوى %@.",
                "I’m EnglishNova’s local backup tutor. The server provides smarter coaching, while locally I can help correct common English sentences and continue short practice at level %@.",
                level.rawValue
            )
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
            return LE(
                "أنا المدرّب المحلي الاحتياطي في EnglishNova. أعمل داخل الجهاز عندما لا تصل خدمة المدرّب عبر الإنترنت. أستطيع مساعدتك في تدريب قصير وتصحيح بعض الأخطاء الشائعة، لكن الردود المتقدمة تأتي من المدرّب الذكي عند توفر الاتصال.",
                "I’m EnglishNova’s local backup tutor. I run on the device when the online tutor service cannot be reached. I can help with short practice and some common corrections, while advanced responses come from the smart tutor when available."
            )
        }

        return LfE(
            "فهمت رسالتك العربية. المدرّب المحلي لا يحوّل النص العربي إلى جملة إنجليزية عشوائيًا. إذا أردت التعلّم، اكتب الجملة الإنجليزية التي تريد تصحيحها، أو اطلب تمرينًا قصيرًا مناسبًا لمستوى %@.",
            "I understood your Arabic message. The local tutor will not turn Arabic text into an unrelated English sentence. To practise, write the English sentence you want corrected or ask for a short exercise suitable for level %@.",
            level.rawValue
        )
    }

    private func startsLikeQuestion(_ lower: String) -> Bool {
        let starters = ["who ", "what ", "where ", "when ", "why ", "how ", "can ", "could ", "do ", "does ", "did ", "is ", "are ", "am ", "will ", "would ", "should "]
        return starters.contains { lower.hasPrefix($0) }
    }

    private func levelAwareFallback(for sentence: String, level: CEFRLevel) -> String {
        switch level {
        case .a0, .a1:
            return LfE(
                "وصلتني الجملة: “%@”. في الوضع المحلي سأركز على جملة قصيرة صحيحة بدل اختراع تتمة لها. راجع ترتيب الفاعل ثم الفعل ثم بقية المعنى، أو اطلب مني تصحيح جملة محددة.",
                "I received the sentence: “%@”. In local mode I’ll focus on a short correct sentence instead of inventing an ending. Check subject, verb, then the rest of the meaning, or ask me to correct a specific sentence.",
                sentence
            )
        case .a2:
            return LfE(
                "وصلتني الجملة: “%@”. اجعلها أوضح بإضافة معلومة واحدة فقط، مثل الزمن أو المكان أو السبب، لكن لا تضف كلمات لا تخدم المعنى الذي تقصده.",
                "I received the sentence: “%@”. Make it clearer by adding just one useful detail, such as time, place, or reason, without adding words that change your intended meaning.",
                sentence
            )
        case .b1, .b2, .c1:
            return LfE(
                "وصلتني الجملة: “%@”. في الوضع المحلي أستطيع إعطاء ملاحظة عامة فقط. طوّر الفكرة بتفصيل مرتبط بالمعنى، ثم راجع الدقة والترابط. للحصول على تحليل لغوي كامل استخدم المدرّب عبر الإنترنت.",
                "I received the sentence: “%@”. In local mode I can provide only general guidance. Develop the idea with a relevant detail, then review accuracy and cohesion. Use the online tutor for full language analysis.",
                sentence
            )
        }
    }
}

struct LocalVoiceCoachEngine {
    func reply(to request: VoiceCoachRequest) -> VoiceCoachReply {
        let normalized = request.learnerTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        let encouragement: String
        if request.localScore >= 0.82 {
            encouragement = LE(
                "ردك مناسب وواضح. حافظ على هذا الإيقاع وأضف تفصيلًا صغيرًا عندما يكون الموقف رسميًا.",
                "Your response is appropriate and clear. Keep this pace and add a small detail when the situation is formal."
            )
        } else if request.localScore >= 0.58 {
            encouragement = LE(
                "المعنى وصل، لكن يمكن جعل الرد أدق بإضافة الفكرة الأساسية بعبارة قصيرة مباشرة.",
                "Your meaning came through, but the response can be more precise by stating the main idea in one short direct phrase."
            )
        } else {
            encouragement = LE(
                "ابدأ بجملة أقصر، ثم أضف سببًا واحدًا. لا تحاول بناء إجابة طويلة من المحاولة الأولى.",
                "Start with a shorter sentence, then add one reason. Do not try to build a long answer on the first attempt."
            )
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
            translationAr: LE("أفهم. ما السبب الرئيسي لذلك؟", "I understand. What is the main reason for that?"),
            feedbackAr: encouragement,
            suggestedAnswer: request.localScore < 0.58 ? "I think this is important because it helps people." : nil,
            source: "local"
        )
    }
}
