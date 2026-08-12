import Foundation

enum CEFRLevel: String, Codable, CaseIterable, Identifiable {
    case a0 = "A0"
    case a1 = "A1"
    case a2 = "A2"
    case b1 = "B1"
    case b2 = "B2"
    case c1 = "C1"

    var id: String { rawValue }

    var titleAr: String {
        switch self {
        case .a0: return L("تمهيدي")
        case .a1: return L("مبتدئ")
        case .a2: return L("أساسي")
        case .b1: return L("متوسط")
        case .b2: return L("متوسط متقدم")
        case .c1: return L("متقدم")
        }
    }

    var summaryAr: String {
        switch self {
        case .a0: return L("ابدأ بالحروف والأصوات والكلمات الأكثر استخدامًا.")
        case .a1: return L("عرّف بنفسك وافهم عبارات وجملًا يومية بسيطة.")
        case .a2: return L("تعامل مع المواقف اليومية واكتب وصفًا قصيرًا وواضحًا.")
        case .b1: return L("تحدث باستقلالية أكبر واكتب نصوصًا مترابطة عن موضوعات مألوفة.")
        case .b2: return L("ناقش أفكارًا أوسع وافهم نصوصًا ومحادثات أكثر تعقيدًا.")
        case .c1: return L("استخدم الإنجليزية بمرونة في الدراسة والعمل والنقاشات المتقدمة.")
        }
    }
}
