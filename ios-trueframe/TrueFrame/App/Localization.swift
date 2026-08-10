import Foundation
import SwiftUI
import Combine
import UIKit

public enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system, en, ar
    public var id: String { rawValue }

    public var displayNativeName: String {
        switch self {
        case .system: return "System"
        case .en: return "English"
        case .ar: return "العربية"
        }
    }
}

public final class AppSettings: ObservableObject {
    public static let shared = AppSettings()

    @Published public var language: AppLanguage {
        didSet { defaults.set(language.rawValue, forKey: "app_language") }
    }
    @Published public var verbosity: Verbosity {
        didSet { defaults.set(verbosity.rawValue, forKey: "verbosity") }
    }
    @Published public var interfaceMode: String {
        didSet { defaults.set(interfaceMode, forKey: "interface_mode") }
    }
    @Published public var hapticFirst: Bool {
        didSet { defaults.set(hapticFirst, forKey: "haptic_first") }
    }
    @Published public var autoCapture: Bool {
        didSet { defaults.set(autoCapture, forKey: "auto_capture") }
    }

    private let defaults = UserDefaults.standard

    private init() {
        language = AppLanguage(rawValue: defaults.string(forKey: "app_language") ?? "system") ?? .system
        verbosity = Verbosity(rawValue: defaults.object(forKey: "verbosity") as? Int ?? Verbosity.normal.rawValue) ?? .normal
        interfaceMode = defaults.string(forKey: "interface_mode")
            ?? (UIAccessibility.isVoiceOverRunning ? "Blind" : "Standard")
        hapticFirst = defaults.object(forKey: "haptic_first") as? Bool
            ?? UIAccessibility.isVoiceOverRunning
        autoCapture = defaults.object(forKey: "auto_capture") as? Bool ?? false
    }

    public var effectiveCode: String {
        switch language {
        case .en:
            return "en"
        case .ar:
            return "ar"
        case .system:
            let preferred = Locale.preferredLanguages.first ?? "en"
            return preferred.hasPrefix("ar") ? "ar" : "en"
        }
    }

    public var isArabic: Bool { effectiveCode == "ar" }
    public var layoutDirection: LayoutDirection { isArabic ? .rightToLeft : .leftToRight }

    public func t(_ english: String) -> String {
        guard isArabic else { return english }
        return Strings.ar[english] ?? english
    }
}

enum Strings {
    static let ar: [String: String] = [
        // Home
        "Take Photo": "التقاط صورة",
        "Import Photo": "اختيار صورة من الألبوم",
        "Recent Photos": "الصور المحفوظة",
        "Settings": "الإعدادات",
        "Accessible camera": "كاميرا ميسّرة",
        "Get clear spoken and haptic guidance while you frame the shot.": "احصل على توجيه صوتي واهتزازات واضحة أثناء ضبط الصورة.",
        "Opens the accessible camera with leveling and framing guidance.": "يفتح الكاميرا مع توجيه صوتي واهتزازات تساعدك على ضبط الميل والإطار.",
        "Choose an existing photo and straighten it without generative editing.": "اختر صورة موجودة وعدّل استقامتها من دون تغيير محتواها بالذكاء الاصطناعي.",
        "Browse corrected copies saved by TrueFrame.": "استعرض النسخ المصححة التي حفظها TrueFrame.",
        "Change language, guidance, accessibility, and auto capture.": "غيّر اللغة وطريقة التوجيه وإعدادات سهولة الاستخدام والالتقاط التلقائي.",

        // Camera
        "Point the camera at your subject.": "وجّه الكاميرا نحو ما تريد تصويره.",
        "Check alignment": "تحقق من وضع الكاميرا",
        "Capture": "التقاط",
        "Close": "إغلاق",
        "Camera ready": "الكاميرا جاهزة",
        "Camera starting": "جارٍ تجهيز الكاميرا",
        "Camera is level": "الهاتف مستقيم",
        "Camera is tilted": "الهاتف مائل",
        "Speaks the most important adjustment.": "ينطق أهم تعديل تحتاجه الآن.",
        "Takes the photo. You will hear a quality report.": "يلتقط الصورة، ثم يعرض لك تقريرًا عن جودتها.",
        "Capture failed. Try again.": "تعذر التقاط الصورة. حاول مرة أخرى.",
        "Camera error. Try again.": "حدثت مشكلة في الكاميرا. حاول مرة أخرى.",
        "Auto capture is on": "الالتقاط التلقائي مفعّل",

        // Review
        "Review": "مراجعة الصورة",
        "Quality Report": "تقييم جودة الصورة",
        "Fix alignment": "تصحيح الميل",
        "Rotates to level and crops the empty corners. No generative editing.": "يصحح ميل الصورة ويقص الزوايا الفارغة فقط، من دون تعديل توليدي.",
        "Before and After": "ما الذي تغير؟",
        "Read text": "قراءة النص في الصورة",
        "Recognized Text": "النص الموجود في الصورة",
        "No text found.": "لم يُعثر على نص واضح في الصورة.",
        "Reading text…": "جارٍ قراءة النص…",
        "Save corrected copy": "حفظ نسخة مصححة",
        "Saves a new copy. Your original is never changed.": "يحفظ نسخة جديدة ويترك الصورة الأصلية كما هي.",
        "Saving…": "جارٍ الحفظ…",
        "Saved a corrected copy. Original preserved.": "تم حفظ نسخة مصححة، والصورة الأصلية لم تتغير.",
        "Captured photo": "الصورة الملتقطة",
        "Corrected photo": "الصورة بعد التصحيح",
        "Done": "تم",
        "Rotation angle": "مقدار تعديل الميل",
        "Straighten": "تصحيح الاستقامة",
        "Decrease angle": "تقليل التصحيح",
        "Increase angle": "زيادة التصحيح",
        "Snap to level": "استخدام ميل الهاتف وقت الالتقاط",
        "Step": "دقة التعديل",
        "Could not correct this photo.": "تعذر تصحيح هذه الصورة.",
        "Save failed.": "تعذر حفظ الصورة.",

        // Settings
        "Language": "اللغة",
        "System": "حسب لغة الجهاز",
        "Appearance": "طريقة الاستخدام",
        "Interface Mode": "نمط الواجهة",
        "Blind": "كفيف",
        "Low Vision": "ضعيف البصر",
        "Standard": "قياسي",
        "Speech Detail": "تفصيل التوجيه الصوتي",
        "Guidance": "التوجيه أثناء التصوير",
        "Auto capture waits for a stable ready scene and will not fire repeatedly.": "ينتظر الالتقاط التلقائي حتى تثبت الصورة وتصبح جاهزة، ولن يلتقط عدة صور متتالية بلا سبب.",
        "Blind mode keeps screens concise and relies more on VoiceOver and haptics.": "نمط الكفيف يبسط الشاشات ويعتمد أكثر على VoiceOver والاهتزازات.",
        "Low Vision mode uses larger text, larger controls, and stronger visual emphasis.": "نمط ضعف البصر يستخدم نصوصًا وأزرارًا أكبر وتباينًا بصريًا أوضح.",
        "Standard mode balances visual detail with accessibility guidance.": "النمط القياسي يوازن بين التفاصيل المرئية وإرشادات سهولة الاستخدام.",
        "Minimal": "مختصر جدًا",
        "Normal": "متوازن",
        "Detailed": "مفصل",
        "Haptic-first leveling": "استخدم الاهتزاز لضبط الميل",
        "Reserve speech for framing; use haptics for leveling.": "اجعل الاهتزاز يساعدك في ضبط ميل الهاتف، واترك الصوت لتوجيه الإطار والمشكلات المهمة.",
        "Auto capture when ready": "التقاط تلقائي بعد ثبات الصورة",
        "Captures automatically when level, sharp, and framed.": "يلتقط الصورة تلقائيًا بعد أن تصبح مستقيمة وواضحة وثابتة لفترة قصيرة.",
        "Authenticity": "طريقة تصحيح الصور",
        "The Fix Photo workflow only rotates, corrects perspective, and crops. It never uses generative AI.": "تصحيح الصورة يقتصر على الميل والمنظور والقص. لا يُنشئ عناصر جديدة ولا يغيّر محتوى المشهد بالذكاء الاصطناعي.",

        // Recent
        "No corrected photos yet.": "لا توجد صور مصححة محفوظة حتى الآن.",
        "Rotation": "تعديل الميل",
        "Cropped": "تم القص",
        "Generative": "تعديل توليدي",
        "None": "لا يوجد",
        "Yes": "نعم"
    ]
}
