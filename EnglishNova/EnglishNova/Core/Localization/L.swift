import Foundation

/// Build-independent localization.
/// Arabic is the source language. English resolves through OTA overrides,
/// the bundled JSON map, standard en.lproj resources, then small dynamic rules.
final class Localizer {
    static let shared = Localizer()

    var isEnglish = false

    private var map: [String: String] = [:]
    private var overrides: [String: String] = [:]
    private lazy var englishBundle: Bundle? = {
        guard let path = Bundle.main.path(forResource: "en", ofType: "lproj") else { return nil }
        return Bundle(path: path)
    }()

    private var overridesCacheURL: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("i18n-overrides.json")
    }

    private init() {
        isEnglish = UserDefaults.standard.string(forKey: "ui.language") == "en"
        load()
        loadCachedOverrides()
    }

    private func load() {
        map = loadMap(named: "translations")
        for index in 1...6 {
            let supplemental = loadMap(named: "interface_en_\(index)")
            map.merge(supplemental) { _, newer in newer }
        }
    }

    private func loadMap(named name: String) -> [String: String] {
        let url = Bundle.main.url(forResource: name, withExtension: "json",
                                  subdirectory: "LocalizationData")
            ?? Bundle.main.url(forResource: name, withExtension: "json")
        guard let url,
              let data = try? Data(contentsOf: url),
              let dict = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        return dict
    }

    private func loadCachedOverrides() {
        guard let url = overridesCacheURL,
              let data = try? Data(contentsOf: url),
              let dict = try? JSONDecoder().decode([String: String].self, from: data)
        else { return }
        overrides = dict
    }

    func translate(_ arabic: String) -> String {
        guard isEnglish else { return ArabicInterfaceCopy.polish(arabic) }

        if let translated = valid(overrides[arabic], source: arabic) { return translated }
        if let translated = valid(map[arabic], source: arabic) { return translated }
        if let translated = valid(EnglishInterfaceCopy.exact[arabic], source: arabic) { return translated }
        if let translated = bundledEnglish(for: arabic) { return translated }
        if let translated = EnglishInterfaceCopy.dynamic(arabic) { return translated }

        if Self.containsArabic(arabic) {
            #if DEBUG
            print("[Localization] Missing English copy: \(arabic)")
            #endif
            return EnglishInterfaceCopy.unavailable
        }
        return arabic
    }

    private func valid(_ value: String?, source: String) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty,
              value != source else { return nil }
        return value
    }

    private func bundledEnglish(for key: String) -> String? {
        guard let bundle = englishBundle else { return nil }
        let value = bundle.localizedString(forKey: key, value: nil, table: "Localizable")
        return valid(value, source: key)
    }

    func refreshFromServer() async {
        guard let base = ServerEndpoint.currentURL else { return }
        var comps = URLComponents(url: base.appendingPathComponent("content"), resolvingAgainstBaseURL: false)
        comps?.queryItems = [URLQueryItem(name: "channel", value: "i18n")]
        guard let url = comps?.url else { return }
        struct ContentResponse: Decodable { let payload: [String: String]? }
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 15
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  data.count <= 5 * 1_024 * 1_024 else { return }
            let decoded = try JSONDecoder().decode(ContentResponse.self, from: data)
            guard let payload = decoded.payload, !payload.isEmpty else { return }
            overrides = payload
            if let cache = overridesCacheURL, let encoded = try? JSONEncoder().encode(payload) {
                try? encoded.write(to: cache, options: .atomic)
            }
        } catch {
            // Keep cached and bundled localization when offline.
        }
    }

    private static func containsArabic(_ value: String) -> Bool {
        value.unicodeScalars.contains { scalar in
            (0x0600...0x06FF).contains(Int(scalar.value)) ||
            (0x0750...0x077F).contains(Int(scalar.value)) ||
            (0x08A0...0x08FF).contains(Int(scalar.value))
        }
    }
}

enum ArabicInterfaceCopy {
    private static let exact: [String: String] = [
        "خطتك الذكية": "خطة اليوم",
        "خطتي الذكية": "خطة اليوم",
        "مدربك الشخصي": "اقتراحات لك",
        "مختبرات": "تدريب المهارات",
        "مختبرات المستوى المتقدم": "تدريب المهارات",
        "ذكاء الخادم": "أدوات الذكاء الاصطناعي",
        "استوديو المحادثة": "تدريب المحادثة",
        "مختبر النطق": "تدريب النطق",
        "مختبر الاستماع": "تدريب الاستماع",
        "مصنع الجمل": "بناء الجمل",
        "المراجعة الذكية": "المراجعة",
        "مدرب الكتابة الذكي": "تدريب الكتابة",
        "المدرب الصوتي الجديد": "المحادثة بالصوت",
        "محادثة صوتية ذكية": "تدريب المحادثة بالصوت",
        "تدريب ذكي": "تدريب مخصص",
        "درّبني على نقاط ضعفي": "اختر تدريبًا مناسبًا لي",
        "الأخطاء التي سيتذكرها المدرب": "تصحيحات محفوظة للتدريب القادم",
        "مراجعة ذكية": "مراجعة",
        "مصحّح الكتابة": "تدريب الكتابة",
        "مولّد التمارين": "تمارين مخصصة",
        "موجز المدرب الذكي": "اقتراح المدرب",
        "أنشئ تدريبًا من نقاط ضعفي": "أنشئ تدريبًا يناسب احتياجي",
        "لوحة الصدارة": "الترتيب",
        "تحليلات التقدم": "تحليل التقدّم",
        "قاموسي الشخصي": "دفتر المفردات",
        "توصياتنا لك": "الخطوة التالية",
        "إجابة صحيحة": "صحيح",
        "لنصححها معًا": "راجع الإجابة",
        "تقييمك": "نتيجتك",
        "فوق المتوسط": "متوسط متقدم",
        "تمهيدي من الصفر": "تمهيدي",
        "أداء ممتاز! 🎉": "ممتاز! 🎉",
        "أداء جيد جدًا 👏": "جيد جدًا 👏"
    ]

    private static let phraseReplacements: [(String, String)] = [
        ("جاري ", "جارٍ "), ("إضغط", "اضغط"), ("إختار", "اختر"),
        ("إستمع", "استمع"), ("إستخدم", "استخدم"), ("إكتب", "اكتب"),
        ("اولا", "أولًا"), ("ثانيا", "ثانيًا"),
        ("اللغة الانجليزية", "اللغة الإنجليزية"), ("اللغه الإنجليزية", "اللغة الإنجليزية"),
        ("اللغة العربيه", "اللغة العربية"), ("  ", " "), (" ،", "،"),
        (" .", "."), (" ؟", "؟"), (" !", "!")
    ]

    static func polish(_ input: String) -> String {
        guard !input.isEmpty else { return input }
        if let replacement = exact[input] { return replacement }
        var text = input
        for (bad, good) in phraseReplacements {
            text = text.replacingOccurrences(of: bad, with: good)
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private enum EnglishInterfaceCopy {
    static let unavailable = "Translation unavailable"

    static let exact: [String: String] = [
        "الدراسة": "Learning", "تفضيلات التعلّم": "Learning preferences",
        "الصوت والمحادثة": "Speech and conversation", "المدرّب والذكاء الاصطناعي": "Tutor and AI",
        "التذكيرات": "Reminders", "البيانات والمزامنة": "Data and sync",
        "الخصوصية والمعلومات": "Privacy and information", "المساعدة والتواصل": "Help and contact",
        "شروط الاستخدام": "Terms of Use", "الخصوصية": "Privacy", "البيانات التي نستخدمها": "Data we use",
        "كيف نستخدم الذكاء الاصطناعي": "How we use AI", "بيانات تبقى على جهازك": "Data that stays on your device",
        "حذف الحساب والبيانات": "Account and data deletion", "التعلّم وليس ضمانًا للنتيجة": "Learning, not a guaranteed result",
        "الاستخدام المقبول": "Acceptable use", "توفر الخدمة": "Service availability", "حسابك": "Your account",
        "المحتوى والحقوق": "Content and rights", "التغييرات": "Changes", "تواصل معنا": "Contact us",
        "آخر تحديث: 12 أغسطس 2026": "Last updated: August 12, 2026", "اقتراح المدرب": "Tutor suggestion",
        "تدريب النطق": "Pronunciation practice", "تدريب الاستماع": "Listening practice",
        "تدريب المحادثة": "Conversation practice", "بناء الجمل": "Sentence building",
        "تمارين مخصصة": "Personalized exercises", "تدريب الكتابة": "Writing practice",
        "دفتر المفردات": "Vocabulary notebook", "تحليل التقدّم": "Progress insights", "الترتيب": "Leaderboard",
        "تدريب المهارات": "Skills practice", "الخطوة التالية": "Next step", "راجع الإجابة": "Review the answer",
        "نتيجتك": "Your result", "مراجعة ذكية قصيرة لتثبيت الذاكرة": "A short spaced-review session to strengthen retention",
        "جارٍ إعداد خطة اليوم": "Preparing today's plan", "جارٍ إعداد التقرير": "Preparing your report",
        "أسبوع ثابت وقوي. الاستمرارية هنا أهم من جلسة طويلة منفردة.": "A strong, consistent week. Regular practice matters more than one long session.",
        "الإيقاع جيد، ويحتاج يومين قصيرين إضافيين حتى تصبح اللغة عادة أسبوعية.": "Your rhythm is good. Two more short days would make practice more consistent.",
        "النشاط متقطع. ثلاث جلسات من عشر دقائق ستكون أكثر فائدة من انتظار يوم مثالي.": "Practice was irregular. Three ten-minute sessions would be more useful than waiting for a perfect day.",
        "اكتب مسودة واحدة ثم أعد كتابتها بعد قراءة التقييم.": "Write one draft, review the feedback, then rewrite it.",
        "نفّذ مقطعي استماع، الأول دون نص والثاني مع كشف النص في النهاية.": "Complete two listening tasks: first without a transcript, then reveal it at the end of the second.",
        "حافظ على أربع جلسات قصيرة موزعة بدل جلسة واحدة ثقيلة.": "Aim for four short sessions across the week instead of one heavy session."
    ]

    static func dynamic(_ source: String) -> String? {
        if let captures = match(source, pattern: #"^(\d+) دقائق، (\d+) كلمات جديدة$"#) {
            return "\(captures[0]) min, \(captures[1]) new words"
        }
        if let captures = match(source, pattern: #"^راجع (\d+) كلمة مستحقة$"#) {
            return "Review \(captures[0]) due words"
        }
        if let captures = match(source, pattern: #"^راجع (\d+) بطاقة مستحقة على دفعتين\.$"#) {
            return "Review \(captures[0]) due cards in two short sets."
        }
        if let captures = match(source, pattern: #"^نفّذ جلستين في مهارة (.+)\.$"#) {
            return "Complete two sessions in \(captures[0])."
        }
        if let captures = match(source, pattern: #"^(\d+) يومًا$"#) {
            return "\(captures[0]) days"
        }
        if let captures = match(source, pattern: #"^(\d+) دقيقة$"#) {
            return "\(captures[0]) min"
        }
        if let captures = match(source, pattern: #"^دقتها الحالية (\d+)٪، لذا تستحق نشاطًا إضافيًا قصيرًا\.$"#) {
            return "Current accuracy is \(captures[0])%, so a short extra activity is recommended."
        }
        return nil
    }

    private static func match(_ value: String, pattern: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let result = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
              result.range.location != NSNotFound else { return nil }
        return (1..<result.numberOfRanges).compactMap { index in
            guard let range = Range(result.range(at: index), in: value) else { return nil }
            return String(value[range])
        }
    }
}

func L(_ arabic: String) -> String { Localizer.shared.translate(arabic) }

func LE(_ arabic: String, _ english: String) -> String {
    Localizer.shared.isEnglish ? english : ArabicInterfaceCopy.polish(arabic)
}

func Lf(_ arabicTemplate: String, _ args: String...) -> String {
    var result = Localizer.shared.translate(arabicTemplate)
    for arg in args {
        guard let range = result.range(of: "%@") else { break }
        result.replaceSubrange(range, with: arg)
    }
    return result
}

func LfE(_ arabicTemplate: String, _ englishTemplate: String, _ args: String...) -> String {
    var result = Localizer.shared.isEnglish ? englishTemplate : ArabicInterfaceCopy.polish(arabicTemplate)
    for arg in args {
        guard let range = result.range(of: "%@") else { break }
        result.replaceSubrange(range, with: arg)
    }
    return result
}
