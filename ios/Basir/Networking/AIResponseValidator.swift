import Foundation

enum AIResponseValidator {
    private static let maximumCharacters = 500_000
    private static let forbiddenFragments = [
        "system_instruction", "system instruction:", "prompt contract:",
        "model_candidates", "trusted task instruction:", "quality repair pass:",
        "basir-prompts-", "basir-ai-2026", "hidden reasoning", "thinkinglevel"
    ]

    static func validate(
        _ response: String,
        task: TaskKind,
        sourceInput: String = "",
        policy explicitPolicy: AITaskPolicy? = nil,
        responseSchemaOverride: [String: Any]? = nil
    ) throws -> String {
        let policy = explicitPolicy ?? AITaskPolicyCatalog.policy(for: task)
        let effectiveSchema = responseSchemaOverride ?? policy.responseSchema
        var normalized = response.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { throw GeminiError.decode("empty response") }
        if effectiveSchema != nil { normalized = stripJsonFence(normalized) }
        guard normalized.count <= maximumCharacters else {
            throw GeminiError.decode("response exceeded the safe size limit")
        }
        guard normalized.count >= policy.minimumUsefulCharacters else {
            throw GeminiError.decode("response was too short to be useful")
        }

        let lowered = normalized.lowercased()
        if forbiddenFragments.contains(where: { lowered.contains($0) }) || containsBoundaryLeak(lowered) {
            throw GeminiError.decode("response exposed or followed internal instructions")
        }
        try rejectExplosiveRepetition(normalized)
        try rejectUnwantedPreamble(normalized, profile: policy.validationProfile)

        if policy.preserveCriticalTokens {
            try preserveCriticalTokens(source: sourceInput, output: normalized)
        }

        switch policy.validationProfile {
        case .visualSafety:
            try validateVisualSafety(normalized)
        case .faithfulText, .documentGrounded:
            try validateNoUnsupportedHighRiskAdvice(source: sourceInput, output: normalized)
        default:
            break
        }

        guard effectiveSchema != nil else { return normalized }
        let object = try jsonObject(normalized)
        if task == .convert, responseSchemaOverride != nil {
            try validateDocumentPage(object, sourceInput: sourceInput)
            return normalized
        }
        try validateStructuredObject(object, task: task)
        return try renderStructuredObject(object, task: task, rawJSON: normalized)
    }

    private static func stripJsonFence(_ value: String) -> String {
        var text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.hasPrefix("```") else { return text }
        if let newline = text.firstIndex(of: "\n") {
            text = String(text[text.index(after: newline)...])
        }
        if text.hasSuffix("```") { text = String(text.dropLast(3)) }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func containsBoundaryLeak(_ lowered: String) -> Bool {
        lowered.range(of: #"<<<basir_data_[a-z0-9]+_(begin|end)>>>"#,
                      options: .regularExpression) != nil
    }

    private static func rejectExplosiveRepetition(_ text: String) throws {
        let lines = text.split(whereSeparator: { $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        if lines.count >= 6 {
            let frequencies = Dictionary(grouping: lines, by: { $0 }).mapValues(\.count)
            if let maximum = frequencies.values.max(), maximum >= 4,
               Double(maximum) / Double(lines.count) > 0.45 {
                throw GeminiError.decode("response contained explosive repetition")
            }
        }
        let words = text.lowercased().split(whereSeparator: { $0.isWhitespace || $0.isNewline })
        guard words.count >= 40 else { return }
        let frequencies = Dictionary(grouping: words, by: { String($0) }).mapValues(\.count)
        if let maximum = frequencies.values.max(), maximum >= 24,
           Double(maximum) / Double(words.count) > 0.55 {
            throw GeminiError.decode("response repeated one token excessively")
        }
    }

    private static func rejectUnwantedPreamble(
        _ text: String,
        profile: AIValidationProfile
    ) throws {
        guard [.faithfulText, .structured, .documentGrounded].contains(profile) else { return }
        let lower = text.lowercased()
        let unwanted = [
            "sure, here", "certainly, here", "here is the requested", "as an ai",
            "بالطبع، إليك", "بالتأكيد، إليك", "إليك النتيجة المطلوبة"
        ]
        if unwanted.contains(where: { lower.hasPrefix($0) }) {
            throw GeminiError.decode("response added an unwanted assistant preamble")
        }
    }

    static func criticalTokens(in text: String) -> Set<String> {
        let patterns = [
            #"https?://[^\s<>()\[\]{}]+"#,
            #"[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}"#,
            #"\+?\d[\d\s()\-]{5,}\d"#,
            #"\b[A-Z]{1,8}[A-Z0-9._/\-]*\d[A-Z0-9._/\-]*\b"#,
            #"\b\d{1,4}(?:[.,:/\-]\d{1,4})+(?:\s?[A-Z]{2,5})?\b"#,
            #"\b\d+(?:[.,]\d+)?\s?(?:SAR|USD|EUR|GBP|AED|ر\.س)\b"#
        ]
        var result = Set<String>()
        let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                continue
            }
            for match in regex.matches(in: text, range: fullRange) {
                guard let range = Range(match.range, in: text) else { continue }
                result.insert(normalizeToken(String(text[range])))
            }
        }
        return result
    }

    private static func preserveCriticalTokens(source: String, output: String) throws {
        guard !source.isEmpty else { return }
        let expected = criticalTokens(in: source)
        guard !expected.isEmpty else { return }
        let actual = criticalTokens(in: output)
        let retained = expected.intersection(actual).count
        let recall = Double(retained) / Double(expected.count)
        guard recall >= 0.90 else {
            throw GeminiError.decode("critical numbers, links, or identifiers changed")
        }
    }

    private static func validateVisualSafety(_ text: String) throws {
        let lower = text.lowercased()
        let forbidden = [
            "the route is safe", "path is safe", "cross the road", "enter traffic",
            "go down the stairs", "اعبر الشارع", "الطريق آمن", "المسار آمن",
            "ادخل حركة المرور", "انزل الدرج"
        ]
        if forbidden.contains(where: { lower.contains($0) }) {
            throw GeminiError.decode("visual response contained unsafe navigation language")
        }
    }

    private static func validateNoUnsupportedHighRiskAdvice(source: String, output: String) throws {
        let outputLower = output.lowercased()
        let sourceLower = source.lowercased()
        let phrases = [
            "stop taking", "double the dose", "sign the contract", "waive your rights",
            "أوقف الدواء", "ضاعف الجرعة", "وقّع العقد", "تنازل عن حقوقك"
        ]
        for phrase in phrases where outputLower.contains(phrase) && !sourceLower.contains(phrase) {
            throw GeminiError.decode("response introduced unsupported high-risk advice")
        }
    }

    private static func jsonObject(_ text: String) throws -> [String: Any] {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GeminiError.decode("response was not valid JSON")
        }
        return object
    }

    private static func validateStructuredObject(_ object: [String: Any], task: TaskKind) throws {
        switch task {
        case .liveScene:
            try validateLiveScene(object)
        case .describeImage:
            try requireNonemptyString(object, "summary")
        case .altText:
            try requireNonemptyString(object, "alt_text")
        case .screenshot:
            let title = string(object, "screen_title")
            let elements = object["elements"] as? [[String: Any]] ?? []
            let messages = strings(object, "messages")
            let errors = strings(object, "errors")
            guard !title.isEmpty || !elements.isEmpty || !messages.isEmpty || !errors.isEmpty else {
                throw GeminiError.decode("screenshot JSON was structurally valid but empty")
            }
        case .currencyOrReceipt:
            let kind = string(object, "kind")
            guard ["banknote", "coin", "receipt", "invoice", "unknown"].contains(kind) else {
                throw GeminiError.decode("currency result contained an invalid kind")
            }
            let note = string(object, "authenticity_note").lowercased()
            guard note.contains("cannot") || note.contains("can't") || note.contains("لا يمكن") || note.contains("لا يستطيع") else {
                throw GeminiError.decode("currency result made no authenticity limitation")
            }
        case .medicalText:
            try requireNonemptyString(object, "document_type")
            try validateMedicationObjects(object["medications"] as? [[String: Any]] ?? [])
        case .legalText:
            try requireNonemptyString(object, "document_type")
        case .tableRead:
            try validateTable(object)
        case .studyCards:
            let cards = object["cards"] as? [[String: Any]] ?? []
            guard !cards.isEmpty else { throw GeminiError.decode("study card JSON contained no cards") }
            for card in cards {
                try requireNonemptyString(card, "question")
                try requireNonemptyString(card, "answer")
            }
        case .walkingSnapshot:
            let obstacle = string(object, "immediate_obstacle")
            let path = string(object, "path")
            let objects = strings(object, "notable_objects")
            guard !obstacle.isEmpty || !path.isEmpty || !objects.isEmpty else {
                throw GeminiError.decode("walking snapshot JSON was empty")
            }
            if let data = try? JSONSerialization.data(withJSONObject: object),
               let text = String(data: data, encoding: .utf8) {
                try validateVisualSafety(text)
            }
            let reminder = string(object, "safety_reminder").lowercased()
            guard reminder.contains("camera") || reminder.contains("الكاميرا") || reminder.contains("mobility") || reminder.contains("العصا") else {
                throw GeminiError.decode("walking snapshot omitted its safety limitation")
            }
        case .ocr:
            try requireNonemptyString(object, "text")
        default:
            break
        }
    }


    private static func validateDocumentPage(_ object: [String: Any], sourceInput: String) throws {
        guard let sections = object["sections"] as? [[String: Any]], !sections.isEmpty else {
            throw GeminiError.decode("document page JSON contained no sections")
        }
        guard sections.count <= 2_000 else {
            throw GeminiError.decode("document page JSON contained too many sections")
        }
        let allowed = Set(["heading", "paragraph", "list_item", "table", "image_description"])
        var visibleCharacterCount = 0
        for section in sections {
            guard let type = section["type"] as? String, allowed.contains(type) else {
                throw GeminiError.decode("document page JSON contained an invalid section type")
            }
            switch type {
            case "heading", "paragraph", "list_item":
                let text = sectionText(section)
                guard !text.isEmpty else {
                    throw GeminiError.decode("document page JSON contained an empty text section")
                }
                visibleCharacterCount += text.count
            case "table":
                guard let rows = section["cells"] as? [[Any]], !rows.isEmpty else {
                    throw GeminiError.decode("document page table contained no rows")
                }
                let width = rows.first?.count ?? 0
                guard width > 0, width <= 50, rows.count <= 500, rows.allSatisfy({ $0.count == width }) else {
                    throw GeminiError.decode("document page table was not rectangular or exceeded safe limits")
                }
                visibleCharacterCount += rows.flatMap { $0 }.map { String(describing: $0) }.joined().count
            case "image_description":
                let description = string(section, "description")
                guard !description.isEmpty else {
                    throw GeminiError.decode("document image description was empty")
                }
                visibleCharacterCount += description.count
            default:
                break
            }
        }
        if !sourceInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           visibleCharacterCount == 0 {
            throw GeminiError.decode("document page JSON contained no visible content")
        }
    }

    private static func sectionText(_ section: [String: Any]) -> String {
        if let runs = section["runs"] as? [[String: Any]] {
            let joined = runs.compactMap { $0["text"] as? String }.joined()
            if !joined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return joined }
        }
        return string(section, "text")
    }

    private static func validateLiveScene(_ object: [String: Any]) throws {
        guard let scene = object["scene"] as? String,
              let path = object["path"] as? String,
              !(scene.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty),
              let hazard = object["hazard"] as? [String: Any],
              let level = hazard["level"] as? String,
              let description = hazard["description"] as? String,
              ["stop", "caution", "none"].contains(level),
              (level == "none" || !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) else {
            throw GeminiError.decode("live scene response failed semantic validation")
        }
    }

    private static func validateMedicationObjects(_ medications: [[String: Any]]) throws {
        for medication in medications {
            try requireNonemptyString(medication, "name")
            let combined = ["dose", "unit", "frequency", "printed_instructions"]
                .map { string(medication, $0) }.joined(separator: " ")
            guard !combined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw GeminiError.decode("medication entry omitted all printed details")
            }
        }
    }

    private static func validateTable(_ object: [String: Any]) throws {
        let columns = strings(object, "columns")
        let rows = object["rows"] as? [[String]] ?? []
        guard !columns.isEmpty, !rows.isEmpty else {
            throw GeminiError.decode("table JSON contained no columns or rows")
        }
        guard rows.allSatisfy({ $0.count == columns.count }) else {
            throw GeminiError.decode("table JSON was not rectangular")
        }
    }

    private static func requireNonemptyString(_ object: [String: Any], _ key: String) throws {
        guard !string(object, key).isEmpty else {
            throw GeminiError.decode("structured response omitted \(key)")
        }
    }

    private static func renderStructuredObject(
        _ object: [String: Any],
        task: TaskKind,
        rawJSON: String
    ) throws -> String {
        if task == .liveScene { return rawJSON }
        let arabic = containsArabic(flattenedText(object))
        switch task {
        case .describeImage:
            return sections([
                (label("الخلاصة", "Summary", arabic), [string(object, "summary")]),
                (label("التفاصيل", "Details", arabic), strings(object, "details")),
                (label("النص الظاهر", "Visible text", arabic), strings(object, "visible_text")),
                (label("مواضع عدم اليقين", "Uncertainties", arabic), strings(object, "uncertainties"))
            ])
        case .altText:
            return sections([
                (label("الوصف البديل", "Alt text", arabic), [string(object, "alt_text")]),
                (label("تفاصيل مهمة", "Key details", arabic), strings(object, "key_details")),
                (label("النص الظاهر", "Visible text", arabic), strings(object, "visible_text")),
                (label("عدم اليقين", "Uncertainties", arabic), strings(object, "uncertainties"))
            ])
        case .screenshot:
            var elementLines: [String] = []
            for element in object["elements"] as? [[String: Any]] ?? [] {
                let parts = [string(element, "role"), string(element, "label"), string(element, "value"), string(element, "state")]
                    .filter { !$0.isEmpty }
                if !parts.isEmpty { elementLines.append(parts.joined(separator: ": ")) }
            }
            return sections([
                (label("الشاشة", "Screen", arabic), [string(object, "screen_title")]),
                (label("العناصر بترتيب القراءة", "Elements in reading order", arabic), elementLines),
                (label("الرسائل", "Messages", arabic), strings(object, "messages")),
                (label("الأخطاء", "Errors", arabic), strings(object, "errors")),
                (label("إجراءات محتملة", "Possible next actions", arabic), strings(object, "next_actions"))
            ])
        case .currencyOrReceipt:
            let facts = [
                pair(label("النوع", "Type", arabic), string(object, "kind")),
                pair(label("العملة", "Currency", arabic), string(object, "currency")),
                pair(label("الفئة", "Denomination", arabic), string(object, "denomination")),
                pair(label("الإجمالي", "Total", arabic), string(object, "total")),
                pair(label("الجهة", "Merchant", arabic), string(object, "merchant")),
                pair(label("التاريخ", "Date", arabic), string(object, "date"))
            ].filter { !$0.isEmpty }
            return sections([
                (label("القراءة", "Reading", arabic), facts),
                (label("البنود", "Line items", arabic), strings(object, "line_items")),
                (label("النص الظاهر", "Visible text", arabic), strings(object, "visible_text")),
                (label("عدم اليقين", "Uncertainties", arabic), strings(object, "uncertainties")),
                (label("تنبيه الأصالة", "Authenticity note", arabic), [string(object, "authenticity_note")])
            ])
        case .medicalText:
            var details = keyValueLines(object["patient_details"] as? [[String: Any]] ?? [])
            var medications: [String] = []
            for item in object["medications"] as? [[String: Any]] ?? [] {
                medications.append([string(item, "name"), string(item, "dose"), string(item, "unit"), string(item, "frequency"), string(item, "printed_instructions")]
                    .filter { !$0.isEmpty }.joined(separator: "، "))
            }
            details.insert(pair(label("نوع المستند", "Document type", arabic), string(object, "document_type")), at: 0)
            return sections([
                (label("بيانات المستند", "Document details", arabic), details),
                (label("الأدوية المطبوعة", "Printed medications", arabic), medications),
                (label("النتائج أو الملاحظات", "Findings", arabic), strings(object, "findings")),
                (label("التواريخ", "Dates", arabic), strings(object, "dates")),
                (label("التحذيرات المطبوعة", "Printed warnings", arabic), strings(object, "printed_warnings")),
                (label("نص غير مقروء", "Unreadable text", arabic), strings(object, "unreadable")),
                (label("تنبيه", "Safety note", arabic), [string(object, "safety_note")])
            ])
        case .legalText:
            var obligations: [String] = []
            for item in object["obligations"] as? [[String: Any]] ?? [] {
                obligations.append([string(item, "party"), string(item, "obligation"), string(item, "deadline"), string(item, "amount")]
                    .filter { !$0.isEmpty }.joined(separator: "، "))
            }
            return sections([
                (label("نوع المستند", "Document type", arabic), [string(object, "document_type")]),
                (label("الأطراف", "Parties", arabic), strings(object, "parties")),
                (label("الالتزامات", "Obligations", arabic), obligations),
                (label("التواريخ", "Dates", arabic), strings(object, "dates")),
                (label("المبالغ", "Amounts", arabic), strings(object, "amounts")),
                (label("النصوص الحاسمة", "Decisive quotes", arabic), strings(object, "decisive_quotes")),
                (label("التوقيعات الظاهرة", "Visible signatures", arabic), strings(object, "signatures")),
                (label("عدم اليقين", "Uncertainties", arabic), strings(object, "uncertainties")),
                (label("تنبيه قانوني", "Legal note", arabic), [string(object, "legal_note")])
            ])
        case .tableRead:
            let title = string(object, "title")
            let columns = strings(object, "columns")
            let rows = object["rows"] as? [[String]] ?? []
            var sectionsOutput: [String] = []
            if !title.isEmpty { sectionsOutput.append(title) }
            for (index, row) in rows.enumerated() {
                let values = zip(columns, row).map { column, value in
                    "\(column): \(value.isEmpty ? "—" : value)"
                }
                let rowTitle = "\(label("الصف", "Row", arabic)) \(index + 1)"
                sectionsOutput.append(rowTitle + ":\n" + values.joined(separator: "\n"))
            }
            let unreadable = strings(object, "unreadable_cells")
            if !unreadable.isEmpty {
                sectionsOutput.append(
                    label("خلايا غير واضحة", "Unclear cells", arabic) + ":\n"
                    + unreadable.map { "- \($0)" }.joined(separator: "\n")
                )
            }
            return sectionsOutput.joined(separator: "\n\n")
        case .studyCards:
            let cards = object["cards"] as? [[String: Any]] ?? []
            return cards.enumerated().map { index, card in
                let question = string(card, "question")
                let answer = string(card, "answer")
                let reference = string(card, "source_reference")
                var value = "\(index + 1). \(label("السؤال", "Question", arabic)): \(question)\n"
                value += "\(label("الإجابة", "Answer", arabic)): \(answer)"
                if !reference.isEmpty { value += "\n\(label("المرجع", "Source", arabic)): \(reference)" }
                return value
            }.joined(separator: "\n\n")
        case .walkingSnapshot:
            return sections([
                (label("العائق الأقرب", "Immediate obstacle", arabic), [string(object, "immediate_obstacle")]),
                (label("المسار الظاهر", "Visible path", arabic), [string(object, "path")]),
                (label("عناصر بارزة", "Notable objects", arabic), strings(object, "notable_objects")),
                (label("النص الظاهر", "Visible text", arabic), strings(object, "visible_text")),
                (label("عدم اليقين", "Uncertainty", arabic), [string(object, "uncertainty")]),
                (label("تنبيه السلامة", "Safety reminder", arabic), [string(object, "safety_reminder")])
            ])
        case .ocr:
            var output = string(object, "text")
            let unreadable = strings(object, "unreadable_segments")
            if !unreadable.isEmpty {
                output += "\n\n" + label("مقاطع غير واضحة", "Unclear segments", arabic) + ":\n"
                output += unreadable.map { "- \($0)" }.joined(separator: "\n")
            }
            return output
        default:
            return rawJSON
        }
    }

    private static func string(_ object: [String: Any], _ key: String) -> String {
        (object[key] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func strings(_ object: [String: Any], _ key: String) -> [String] {
        (object[key] as? [String] ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    private static func keyValueLines(_ items: [[String: Any]]) -> [String] {
        items.compactMap { item in
            let key = string(item, "key")
            let value = string(item, "value")
            guard !key.isEmpty || !value.isEmpty else { return nil }
            return key.isEmpty ? value : "\(key): \(value)"
        }
    }

    private static func sections(_ sections: [(String, [String])]) -> String {
        sections.compactMap { title, values in
            let cleaned = values.filter { !$0.isEmpty }
            guard !cleaned.isEmpty else { return nil }
            if cleaned.count == 1 { return "\(title):\n\(cleaned[0])" }
            return "\(title):\n" + cleaned.map { "- \($0)" }.joined(separator: "\n")
        }.joined(separator: "\n\n")
    }

    private static func pair(_ key: String, _ value: String) -> String {
        value.isEmpty ? "" : "\(key): \(value)"
    }

    private static func flattenedText(_ object: [String: Any]) -> String {
        if let data = try? JSONSerialization.data(withJSONObject: object),
           let text = String(data: data, encoding: .utf8) { return text }
        return ""
    }

    private static func containsArabic(_ text: String) -> Bool {
        text.unicodeScalars.contains { (0x0600...0x06FF).contains(Int($0.value)) }
    }

    private static func label(_ arabic: String, _ english: String, _ useArabic: Bool) -> String {
        useArabic ? arabic : english
    }

    private static func normalizeToken(_ value: String) -> String {
        value
            .trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?،؛"))
            .replacingOccurrences(of: " ", with: "")
            .lowercased()
    }
}
