import Foundation

enum EntryKind: String, Codable, CaseIterable, Identifiable {
    case expense, income, owed, owing
    var id: Self { self }
    var title: String {
        switch self { case .expense: return "مصروف"; case .income: return "دخل"; case .owed: return "دين لي"; case .owing: return "دين عليّ" }
    }
    var icon: String {
        switch self { case .expense: return "cart"; case .income: return "banknote"; case .owed: return "person.crop.circle.badge.checkmark"; case .owing: return "person.2" }
    }
    var isDebt: Bool { self == .owed || self == .owing }
}

enum Money {
    // Store integer halalas. Per-entry and ledger count bounds also bound all sums.
    static let maximum = 99_999_999_999
    static let locale = Locale(identifier: "ar_SA")
    static func digits(_ text: String) -> String {
        text.map { ch in ch.wholeNumberValue.map(String.init) ?? String(ch) }.joined()
            .replacingOccurrences(of: "٫", with: ".").replacingOccurrences(of: "٬", with: ",")
    }
    static func parse(_ input: String) -> Int? {
        let s = digits(input.trimmingCharacters(in: .whitespacesAndNewlines))
        guard s.range(of: #"^(?:[0-9]+|[0-9]{1,3}(?:,[0-9]{3})+)(?:\.[0-9]{1,2})?$"#, options: .regularExpression) != nil else { return nil }
        let parts = s.replacingOccurrences(of: ",", with: "").components(separatedBy: ".")
        guard let whole = Int(parts[0]), whole <= maximum / 100 else { return nil }
        let cents = parts.count == 2 ? Int((parts[1] + "0").prefix(2)) ?? 0 : 0
        let value = whole * 100 + cents
        return (1...maximum).contains(value) ? value : nil
    }
    static func input(_ amount: Int) -> String { String(format: "%lld.%02lld", Int64(amount / 100), Int64(amount % 100)) }
    static func number(_ amount: Int) -> String {
        let style = FloatingPointFormatStyle<Double>.number.locale(locale).precision(.fractionLength(0...2))
        return (Double(amount) / 100).formatted(style)
    }
    static func spoken(_ amount: Int) -> String { number(amount) + " ريال سعودي" }
}

struct Payment: Identifiable, Codable, Equatable {
    var id = UUID()
    var date: Date
    var amount: Int
}

struct Entry: Identifiable, Codable, Equatable {
    var id = UUID()
    var kind: EntryKind
    var title: String
    var amount: Int
    var date: Date
    var category = "أخرى"
    var due: Date?
    var payments: [Payment] = []
    var paid: Int { payments.reduce(0) { $0 + $1.amount } }
    var remaining: Int { amount - paid }
}

struct Book: Codable, Equatable {
    var version = 1
    var entries: [Entry] = []
    var budget = 0
    func validate() throws {
        guard version == 1, entries.count <= 100_000, (0...Money.maximum).contains(budget),
              Set(entries.map(\.id)).count == entries.count else { throw BookError.invalid }
        for e in entries {
            guard !e.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, e.title.count <= 160,
                  (1...Money.maximum).contains(e.amount), e.payments.count <= 10_000,
                  Set(e.payments.map(\.id)).count == e.payments.count,
                  e.kind.isDebt || (e.payments.isEmpty && e.due == nil),
                  e.category.count <= 80, e.payments.allSatisfy({ (1...Money.maximum).contains($0.amount) && $0.date >= e.date }),
                  e.paid <= e.amount, e.due.map({ $0 >= e.date }) ?? true else { throw BookError.invalid }
        }
    }
    func monthly(_ date: Date, kind: EntryKind, calendar: Calendar) -> [Entry] {
        entries.filter { $0.kind == kind && calendar.isDate($0.date, equalTo: date, toGranularity: .month) }
    }
    func totalDebt(_ kind: EntryKind) -> Int {
        entries.filter { $0.kind == kind }.reduce(0) { $0 + $1.remaining }
    }
    mutating func pay(id: UUID, amount: Int, date: Date) throws {
        guard let i = entries.firstIndex(where: { $0.id == id }), entries[i].kind.isDebt,
              amount > 0, amount <= entries[i].remaining, date >= entries[i].date else { throw BookError.payment }
        entries[i].payments.append(Payment(date: date, amount: amount))
    }
}
enum BookError: LocalizedError {
    case invalid, payment, locked
    var errorDescription: String? {
        switch self {
        case .invalid: return "تعذّر اعتماد البيانات. تحقق من المبلغ والتواريخ وصحة النسخة."
        case .payment: return "أدخل دفعة موجبة في حدود المتبقي، بتاريخ يوافق تسجيل الدين أو يليه."
        case .locked: return "تعذّرت قراءة الدفتر. يمكنك إعادة المحاولة أو استعادة نسخة من الإعدادات."
        }
    }
}
