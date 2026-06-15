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
        case .a0: return "تمهيدي من الصفر"
        case .a1: return "مبتدئ"
        case .a2: return "أساسي"
        case .b1: return "متوسط"
        case .b2: return "فوق المتوسط"
        case .c1: return "متقدم"
        }
    }
    var summaryAr: String {
        switch self {
        case .a0: return "الحروف والأصوات والكلمات اليومية الأولى"
        case .a1: return "التعريف بالنفس والجمل البسيطة"
        case .a2: return "المواقف اليومية والوصف المباشر"
        case .b1: return "محادثات مستقلة وكتابة واضحة"
        case .b2: return "نقاشات موسعة وفهم محتوى متقدم"
        case .c1: return "طلاقة أكاديمية ومهنية عالية"
        }
    }
}
