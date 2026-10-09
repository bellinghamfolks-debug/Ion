import Foundation

/// A small library of origins and roasts, and a reader for the words found
/// on a bag of beans.
enum BeanOrigin: String, CaseIterable, Identifiable {
    case ethiopia, colombia, brazil, kenya, yemen, guatemala, indonesia, india

    var id: String { rawValue }
    var title: String { L("library.origin.\(rawValue).title") }
    var notes: String { L("library.origin.\(rawValue).notes") }

    /// Words that name the origin on a bag, in Arabic and English.
    var keywords: [String] {
        switch self {
        case .ethiopia: return ["ethiopia", "ethiopian", "yirgacheffe", "sidamo", "اثيوبيا", "إثيوبيا", "يرغاتشيف"]
        case .colombia: return ["colombia", "colombian", "كولومبيا"]
        case .brazil: return ["brazil", "brasil", "santos", "البرازيل", "برازيل"]
        case .kenya: return ["kenya", "كينيا"]
        case .yemen: return ["yemen", "mocha", "اليمن", "يمني", "خولاني", "حرازي"]
        case .guatemala: return ["guatemala", "antigua", "غواتيمالا"]
        case .indonesia: return ["indonesia", "sumatra", "java", "اندونيسيا", "إندونيسيا", "سومطرة"]
        case .india: return ["india", "indian", "monsooned", "الهند", "هندي"]
        }
    }

    /// Typical roast for the origin's flavour, for the drinks it suits.
    var suitedDrinks: [BeverageID] {
        switch self {
        case .ethiopia, .kenya: return [.coffee, .filterCoffee, .coldBrew]
        case .colombia, .guatemala: return [.espresso, .cappuccino, .americano]
        case .brazil: return [.espresso, .caffeLatte, .flatWhite]
        case .yemen: return [.espresso, .cortado, .coffee]
        case .indonesia, .india: return [.ristretto, .latteMacchiato, .cappuccino]
        }
    }
}

enum BagReader {
    struct Reading: Equatable {
        var name: String?
        var roast: BeanProfile.Roast?
        var kind: BeanProfile.Kind?
        var origin: BeanOrigin?
        var grams: Int?
    }

    /// Reads recognised lines of text from a photo of the bag.
    static func read(_ lines: [String]) -> Reading {
        var reading = Reading()
        let joined = DrinkQuery.normalize(lines.joined(separator: " "))
        func has(_ words: [String]) -> Bool { words.map(DrinkQuery.normalize).contains { joined.contains($0) } }
        if has(["dark", "espresso roast", "داكن", "غامق", "تحميص قوي"]) { reading.roast = .dark }
        else if has(["medium", "متوسط"]) { reading.roast = .medium }
        else if has(["light", "blonde", "فاتح", "تحميص خفيف"]) { reading.roast = .light }
        if has(["robusta", "روبوستا"]) && has(["arabica", "ارابيكا"]) { reading.kind = .blend }
        else if has(["robusta", "روبوستا"]) { reading.kind = .robusta }
        else if has(["100% arabica", "arabica", "ارابيكا"]) { reading.kind = .arabica }
        else if has(["blend", "مزيج", "خلطه"]) { reading.kind = .blend }
        reading.origin = BeanOrigin.allCases.first { has($0.keywords) }
        // "1kg", "500 g", "250غ", "250 جرام"
        let text = lines.joined(separator: " ").lowercased()
        if let match = text.range(of: #"(\d{2,4})\s?(g|gr|gram|grams|غ|غرام|جرام|جم)\b"#, options: .regularExpression) {
            reading.grams = Int(text[match].filter(\.isNumber))
        } else if let match = text.range(of: #"(\d(?:[.,]\d)?)\s?(kg|كغ|كيلو)"#, options: .regularExpression) {
            let number = text[match].replacingOccurrences(of: ",", with: ".").filter { $0.isNumber || $0 == "." }
            reading.grams = Double(number).map { Int($0 * 1000) }
        }
        // The name: the first line with letters that is not just a keyword.
        let keywordish = ["coffee", "beans", "قهوه", "بن", "arabica", "roast", "تحميص"]
        reading.name = lines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { line in
                let normal = DrinkQuery.normalize(line)
                return line.count >= 3 && line.count <= 30 && normal.contains(where: \.isLetter)
                    && !keywordish.contains(normal) && !normal.allSatisfy { $0.isNumber || $0 == " " }
            }
        return reading
    }
}
