import Foundation
import SwiftUI
import Combine

/// Language CHOICE (not a forced conversion): the app follows the system by
/// default, and the user may explicitly pick English or Arabic in Settings.
public enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system, en, ar
    public var id: String { rawValue }
    public var displayNativeName: String {
        switch self { case .system: return "System"; case .en: return "English"; case .ar: return "العربية" }
    }
}

/// App-wide, observable settings backed by UserDefaults. Injected as an
/// EnvironmentObject so a language change re-renders every localized view.
public final class AppSettings: ObservableObject {
    public static let shared = AppSettings()

    @Published public var language: AppLanguage { didSet { defaults.set(language.rawValue, forKey: "app_language") } }
    @Published public var verbosity: Verbosity { didSet { defaults.set(verbosity.rawValue, forKey: "verbosity") } }
    @Published public var interfaceMode: String { didSet { defaults.set(interfaceMode, forKey: "interface_mode") } }
    @Published public var hapticFirst: Bool { didSet { defaults.set(hapticFirst, forKey: "haptic_first") } }
    @Published public var autoCapture: Bool { didSet { defaults.set(autoCapture, forKey: "auto_capture") } }

    private let defaults = UserDefaults.standard

    private init() {
        language = AppLanguage(rawValue: defaults.string(forKey: "app_language") ?? "system") ?? .system
        verbosity = Verbosity(rawValue: defaults.object(forKey: "verbosity") as? Int ?? Verbosity.normal.rawValue) ?? .normal
        interfaceMode = defaults.string(forKey: "interface_mode") ?? "Standard"
        hapticFirst = defaults.bool(forKey: "haptic_first")
        autoCapture = defaults.bool(forKey: "auto_capture")
    }

    /// The concrete language code in effect ("en" or "ar").
    public var effectiveCode: String {
        switch language {
        case .en: return "en"
        case .ar: return "ar"
        case .system:
            let pref = Locale.preferredLanguages.first ?? "en"
            return pref.hasPrefix("ar") ? "ar" : "en"
        }
    }
    public var isArabic: Bool { effectiveCode == "ar" }
    public var layoutDirection: LayoutDirection { isArabic ? .rightToLeft : .leftToRight }

    /// Translate an English source string. Unknown keys fall back to the English
    /// text, so the app is always fully usable even before every string is
    /// translated.
    public func t(_ english: String) -> String {
        guard isArabic else { return english }
        return Strings.ar[english] ?? english
    }
}

/// English → Arabic UI strings. English is the source of truth (used as the key),
/// so adding a string never breaks the build; only the Arabic rendering is
/// looked up here.
enum Strings {
    static let ar: [String: String] = [
        // Home
        "Take Photo": "التقاط صورة",
        "Import Photo": "استيراد صورة",
        "Recent Photos": "الصور الأخيرة",
        "Settings": "الإعدادات",
        "Opens the accessible camera with leveling and framing guidance.": "يفتح الكاميرا الميسّرة مع إرشاد الاستواء والتأطير.",
        // Camera
        "Point the camera at your subject.": "وجّه الكاميرا نحو الهدف.",
        "Is it level?": "هل هي مستوية؟",
        "Capture": "التقاط",
        "Close": "إغلاق",
        "Camera is level": "الكاميرا مستوية",
        "Camera is tilted": "الكاميرا مائلة",
        "Takes the photo. You will hear a quality report.": "يلتقط الصورة، وستسمع تقرير الجودة.",
        "Capture failed. Try again.": "تعذّر الالتقاط. حاول مجددًا.",
        // Review
        "Review": "المراجعة",
        "Quality Report": "تقرير الجودة",
        "Fix alignment": "تصحيح الاستواء",
        "Rotates to level and crops the empty corners. No generative editing.": "يدوّر للاستواء ويقصّ الزوايا الفارغة. بلا تعديل توليدي.",
        "Before and After": "قبل وبعد",
        "Read text": "قراءة النص",
        "Recognized Text": "النص المُتعرَّف",
        "No text found.": "لا يوجد نص.",
        "Reading text…": "جارٍ قراءة النص…",
        "Save corrected copy": "حفظ نسخة مصحّحة",
        "Saves a new copy. Your original is never changed.": "يحفظ نسخة جديدة، ولا يُغيّر الأصل أبدًا.",
        "Saving…": "جارٍ الحفظ…",
        "Saved a corrected copy. Original preserved.": "حُفظت نسخة مصحّحة، والأصل محفوظ.",
        "Captured photo": "الصورة الملتقطة",
        "Corrected photo": "الصورة المصحّحة",
        "Done": "تم",
        "Rotation angle": "زاوية التدوير",
        "Straighten": "تسوية",
        "Decrease angle": "إنقاص الزاوية",
        "Increase angle": "زيادة الزاوية",
        "Snap to level": "محاذاة للاستواء",
        "Step": "الخطوة",
        // Settings
        "Language": "اللغة",
        "System": "النظام",
        "Appearance": "المظهر",
        "Interface Mode": "نمط الواجهة",
        "Blind": "كفيف",
        "Low Vision": "ضعيف البصر",
        "Standard": "قياسي",
        "Speech Detail": "تفصيل النطق",
        "Minimal": "مختصر",
        "Normal": "عادي",
        "Detailed": "مفصّل",
        "Haptic-first leveling": "الاستواء بالاهتزاز أولًا",
        "Reserve speech for framing; use haptics for leveling.": "احفظ النطق للتأطير، واستخدم الاهتزاز للاستواء.",
        "Auto capture when ready": "التقاط تلقائي عند الجاهزية",
        "Captures automatically when level, sharp, and framed.": "يلتقط تلقائيًا عند الاستواء والوضوح والتأطير.",
        "Authenticity": "الأصالة",
        "The Fix Photo workflow only rotates, corrects perspective, and crops. It never uses generative AI.": "مسار تصحيح الصورة يدوّر ويصحّح المنظور ويقصّ فقط. لا يستخدم ذكاءً توليديًا أبدًا.",
        // Recent
        "No corrected photos yet.": "لا توجد صور مصحّحة بعد.",
        "Rotation": "التدوير",
        "Cropped": "المقصوص",
        "Generative": "توليدي",
        "None": "لا شيء",
    ]
}
