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
        case .a0: return L("تمهيدي من الصفر")
        case .a1: return L("مبتدئ")
        case .a2: return L("أساسي")
        case .b1: return L("متوسط")
        case .b2: return L("فوق المتوسط")
        case .c1: return L("متقدم")
        }
    }
    var summaryAr: String {
        switch self {
        case .a0: return L("الحروف والأصوات والكلمات اليومية الأولى")
        case .a1: return L("التعريف بالنفس والجمل البسيطة")
        case .a2: return L("المواقف اليومية والوصف المباشر")
        case .b1: return L("محادثات مستقلة وكتابة واضحة")
        case .b2: return L("نقاشات موسعة وفهم محتوى متقدم")
        case .c1: return L("طلاقة أكاديمية ومهنية عالية")
        }
    }
}
