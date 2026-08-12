import Foundation

/// Build-independent localization.
/// Arabic is the source language. English is resolved from the bundled map or
/// an OTA correction, while Arabic goes through a conservative editorial pass.
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
            return overrides[arabic] ?? map[arabic] ?? arabic
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
            // Keep the cached/bundled localization when offline.
        }
    }
}

/// High-confidence Arabic UI copy corrections. Exact replacements are preferred
/// so the editor never rewrites user content or English learning material.
enum ArabicInterfaceCopy {
    private static let exact: [String: String] = [
        "خطتك الذكية": "خطة اليوم",
        "افتح الخطة لمعرفة سبب اختيار كل نشاط.": "افتح الخطة لمعرفة سبب اختيار هذه الأنشطة.",
        "مدربك الشخصي": "اقتراحات مخصصة لك",
        "هذه الاقتراحات مبنية على تقدمك وأخطائك الحديثة، لا على ترتيب ثابت.": "تتغير هذه الاقتراحات بحسب تقدمك والأخطاء التي تحتاج إلى مراجعة.",
        "وصول سريع": "تدريب إضافي",
        "مختبرات": "مهارات متقدمة",
        "مراجعة ذكية": "مراجعة مستحقة",
        "استماع مركز": "تدريب استماع",
        "دقيقة نطق واضحة": "تدريب نطق قصير",
        "ردود محادثة فورية": "تدريب محادثة",
        "نص وفهم عميق": "قراءة وفهم",
        "مسودة كتابة قصيرة": "تدريب كتابة قصير",
        "محاكاة اختبار مركزة": "محاكاة اختبار قصيرة",
        "توصياتنا لك": "ما الخطوة التالية؟",
        "إجابة صحيحة": "صحيح",
        "لنصححها معًا": "راجع الإجابة",
        "تقييمك": "نتيجتك",
        "أداء جيد، وتستطيع أفضل": "جيد. راجع النقاط التي أخطأت فيها.",
        "بداية جيدة، لنقوّها معًا": "راجع الدرس وحاول مرة أخرى.",
        "خطوة صغيرة اليوم تصنع لغة كاملة غدًا.": "ابدأ بما يمكنك اليوم، وسنبني عليه غدًا.",
        "جاري تجهيز رحلتك التعليمية": "جارٍ تجهيز خطتك التعليمية",
        "لا بأس، أعد الدرس بهدوء وركّز على الشرح أولًا.": "راجع الشرح ثم أعد المحاولة عندما تكون جاهزًا.",
        "محادثة موقف": "تدريب محادثة",
        "تدريب اختبار": "محاكاة اختبار",
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
        ("اللغة الانجليزية", "اللغة الإنجليزية"),
        ("اللغه الإنجليزية", "اللغة الإنجليزية")
    ]

    static func polish(_ input: String) -> String {
        guard !input.isEmpty else { return input }
        if let replacement = exact[input] { return replacement }
        var text = input
        for (bad, good) in phraseReplacements {
            text = text.replacingOccurrences(of: bad, with: good)
        }
        return text
    }
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
