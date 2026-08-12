import Foundation

/// Build-independent localization.
/// Arabic is the source language. English is resolved from the bundled map or
/// an OTA correction. Arabic receives only safe typographic/editorial cleanup;
/// product copy itself should be written naturally at its source.
final class Localizer {
    static let shared = Localizer()

    var isEnglish = false

    private var map: [String: String] = [:]
    private var overrides: [String: String] = [:]

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
        let url = Bundle.main.url(forResource: "translations", withExtension: "json",
                                  subdirectory: "LocalizationData")
            ?? Bundle.main.url(forResource: "translations", withExtension: "json")
        guard let url,
              let data = try? Data(contentsOf: url),
              let dict = try? JSONDecoder().decode([String: String].self, from: data)
        else { return }
        map = dict
    }

    private func loadCachedOverrides() {
        guard let url = overridesCacheURL,
              let data = try? Data(contentsOf: url),
              let dict = try? JSONDecoder().decode([String: String].self, from: data)
        else { return }
        overrides = dict
    }

    func translate(_ arabic: String) -> String {
        if isEnglish {
            return overrides[arabic]
                ?? map[arabic]
                ?? EnglishInterfaceCopy.exact[arabic]
                ?? arabic
        }
        return ArabicInterfaceCopy.polish(arabic)
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
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  data.count <= 5 * 1_024 * 1_024 else { return }
            let decoded = try JSONDecoder().decode(ContentResponse.self, from: data)
            guard let payload = decoded.payload, !payload.isEmpty else { return }
            overrides = payload
            if let cache = overridesCacheURL, let encoded = try? JSONEncoder().encode(payload) {
                try? encoded.write(to: cache, options: .atomic)
            }
        } catch {
            // Keep cached/bundled localization when offline.
        }
    }
}

/// Last-line Arabic sanitation. This is deliberately NOT a translation engine.
/// Natural product copy belongs in the view/model that owns it. These rules only
/// correct high-confidence spelling, punctuation and a few legacy names that may
/// still arrive from old bundled/remote content.
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
        ("جاري ", "جارٍ "),
        ("إضغط", "اضغط"),
        ("إختار", "اختر"),
        ("إستمع", "استمع"),
        ("إستخدم", "استخدم"),
        ("إكتب", "اكتب"),
        ("اولا", "أولًا"),
        ("ثانيا", "ثانيًا"),
        ("اللغة الانجليزية", "اللغة الإنجليزية"),
        ("اللغه الإنجليزية", "اللغة الإنجليزية"),
        ("اللغة العربيه", "اللغة العربية"),
        ("  ", " "),
        (" ،", "،"),
        (" .", "."),
        (" ؟", "؟"),
        (" !", "!")
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

/// Small fallback table for new source-level UI copy added after the original
/// localization bundle was generated. It prevents the English interface from
/// unexpectedly showing Arabic while the OTA/bundled catalog catches up.
private enum EnglishInterfaceCopy {
    static let exact: [String: String] = [
        "الدراسة": "Learning",
        "تفضيلات التعلّم": "Learning preferences",
        "الصوت والمحادثة": "Speech and conversation",
        "المدرّب والذكاء الاصطناعي": "Tutor and AI",
        "التذكيرات": "Reminders",
        "البيانات والمزامنة": "Data and sync",
        "الخصوصية والمعلومات": "Privacy and information",
        "المساعدة والتواصل": "Help and contact",
        "شروط الاستخدام": "Terms of Use",
        "الخصوصية": "Privacy",
        "البيانات التي نستخدمها": "Data we use",
        "كيف نستخدم الذكاء الاصطناعي": "How we use AI",
        "بيانات تبقى على جهازك": "Data that stays on your device",
        "حذف الحساب والبيانات": "Account and data deletion",
        "التعلّم وليس ضمانًا للنتيجة": "Learning, not a guaranteed result",
        "الاستخدام المقبول": "Acceptable use",
        "توفر الخدمة": "Service availability",
        "حسابك": "Your account",
        "المحتوى والحقوق": "Content and rights",
        "التغييرات": "Changes",
        "تواصل معنا": "Contact us",
        "آخر تحديث: 12 أغسطس 2026": "Last updated: August 12, 2026",
        "اقتراح المدرب": "Tutor suggestion",
        "تدريب النطق": "Pronunciation practice",
        "تدريب الاستماع": "Listening practice",
        "تدريب المحادثة": "Conversation practice",
        "بناء الجمل": "Sentence building",
        "تمارين مخصصة": "Personalized exercises",
        "تدريب الكتابة": "Writing practice",
        "دفتر المفردات": "Vocabulary notebook",
        "تحليل التقدّم": "Progress insights",
        "الترتيب": "Leaderboard",
        "تدريب المهارات": "Skills practice",
        "الخطوة التالية": "Next step",
        "راجع الإجابة": "Review the answer",
        "نتيجتك": "Your result"
    ]
}

func L(_ arabic: String) -> String { Localizer.shared.translate(arabic) }

func Lf(_ arabicTemplate: String, _ args: String...) -> String {
    var result = Localizer.shared.translate(arabicTemplate)
    for arg in args {
        guard let range = result.range(of: "%@") else { break }
        result.replaceSubrange(range, with: arg)
    }
    return result
}
