import Foundation

func check(_ condition: Bool, _ label: String) {
    guard condition else { fatalError(label) }
    print("PASS", label)
}
do {
    check(Money.parse("١٬٢٣٤٫٥٠") == 123450, "Arabic currency")
    check(Money.parse("۰٫۰۱") == 1, "One halala")
    for bad in ["1.234", "-5", "0", "1,2", "1e3", "1000000000"] { check(Money.parse(bad) == nil, "Reject " + bad) }
    let fixed = Date(timeIntervalSince1970: 1700000000)
    let expense = try Assistant.draft("دفعت ٣٥ ريال للقهوة", history: [], now: fixed)
    check(expense.kind == .expense && expense.amount == "35.00" && expense.category == "طعام ومقاهٍ", "Expense draft")
    let owed = try Assistant.draft("أقرضت سارة ٢٠٠ ريال", history: [])
    let owing = try Assistant.draft("استلفت من خالد ٥٠٠ ريال", history: [])
    check(owed.kind == .owed && owing.kind == .owing, "Debt direction")
    check(owed.title == "سارة" && owing.title == "خالد", "Counterparty extraction")
    check((try? Assistant.draft("١٠ ثم ٢٠", history: [])) == nil, "Ambiguous amounts")
    let learned = Entry(kind: .expense, title: "متجر سحابة", amount: 1000, date: fixed, category: "تسوق")
    check(Assistant.category(for: "دفعت ٧٠ ريال متجر سحابة", history: [learned]) == "تسوق", "On-device learning")
    let loan = Entry(kind: .owing, title: "اختبار", amount: 50000, date: fixed)
    var b = Book(entries: [learned, loan])
    try b.pay(id: loan.id, amount: 15000, date: fixed)
    check(b.totalDebt(.owing) == 35000, "Partial settlement")
    let old = b
    do { try b.pay(id: loan.id, amount: 35001, date: fixed); fatalError("Excess payment") } catch BookError.payment {}
    check(b == old, "Overpayment preserves balance")
    try b.pay(id: loan.id, amount: 35000, date: fixed)
    check(b.totalDebt(.owing) == 0 && b.entries[1].payments.count == 2, "Full settlement")
    check(b.monthly(fixed, kind: .expense, calendar: .current).count == 1, "Payments excluded from spending")
    try b.validate()
    let backup = try JSONDecoder().decode(Book.self, from: JSONEncoder().encode(b))
    check(backup == b, "Backup round trip")
    b.entries[1].amount = 1
    check((try? b.validate()) == nil, "Inconsistent backup rejected")
} catch { fatalError(error.localizedDescription) }
