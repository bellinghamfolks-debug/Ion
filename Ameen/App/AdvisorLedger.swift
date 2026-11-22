import Foundation

struct LedgerReport {
    let book: Book
    let now: Date
    let calendar: Calendar
    init(_ book: Book, now: Date = Date(), calendar: Calendar = Calendar(identifier: .gregorian)) {
        self.book = book
        self.now = now
        self.calendar = calendar
    }

    func expenses(_ offset: Int = 0) -> [Entry] {
        let month = calendar.date(byAdding: .month, value: offset, to: now) ?? now
        return book.monthly(month, kind: .expense, calendar: calendar)
    }
    func total(_ entries: [Entry]) -> Int { entries.reduce(0) { $0 + $1.amount } }
    var income: Int { total(book.monthly(now, kind: .income, calendar: calendar)) }
    var spent: Int { total(expenses()) }
    var summary: String {
        "الدخل المسجل لهذا الشهر \(Money.spoken(income))، والمصروف \(Money.spoken(spent))، والصافي \(Money.spoken(income-spent)).\nالديون القائمة لك \(Money.spoken(book.totalDebt(.owed)))، وعليك \(Money.spoken(book.totalDebt(.owing)))." +
        (book.budget > 0 ? "\nالميزانية الشهرية \(Money.spoken(book.budget))." : "")
    }
    var comparison: String {
        let previous = expenses(-1)
        guard !previous.isEmpty else { return "مصروف هذا الشهر حتى اليوم \(Money.spoken(spent)). لا توجد مصروفات مسجلة للشهر السابق تسمح بحساب التغير." }
        let last = total(previous), delta = spent-last
        let percent = Int((100 * Double(abs(delta)) / Double(last)).rounded())
        return "مصروف هذا الشهر حتى اليوم \(Money.spoken(spent))، مقابل \(Money.spoken(last)) للشهر السابق كاملًا. " +
            (delta == 0 ? "المبلغان متساويان." : "\(delta > 0 ? "زاد" : "انخفض") المصروف بمقدار \(Money.spoken(abs(delta)))، أي نحو \(percent)٪.")
    }
    var budgetPlan: String {
        guard book.budget > 0 else { return "حدّد ميزانيتك الشهرية من الإعدادات لأحسب المتاح لكل يوم." }
        let balance = book.budget - spent
        guard balance >= 0 else { return "تجاوزت الميزانية المسجلة بمقدار \(Money.spoken(-balance))." }
        let days = (calendar.range(of: .day, in: .month, for: now)?.count ?? 30) - calendar.component(.day, from: now) + 1
        return "تبقى \(Money.spoken(balance)) من ميزانيتك. بتقسيمه على \(days) يومًا بما فيها اليوم، يكون الحد اليومي التقريبي \(Money.spoken(balance / max(days, 1)))."
    }
    var dueDebts: String {
        let today = calendar.startOfDay(for: now)
        let horizon = calendar.date(byAdding: .day, value: 8, to: today) ?? today
        let dates = book.entries.filter { $0.kind.isDebt && $0.remaining > 0 && ($0.due.map { $0 < horizon } ?? false) }.sorted { $0.due! < $1.due! }
        guard !dates.isEmpty else { return "لا توجد ديون قائمة لها موعد متأخر أو استحقاق خلال الأيام السبعة القادمة." }
        let formatter = DateFormatter()
        formatter.locale = Money.locale; formatter.calendar = calendar; formatter.dateFormat = "d MMMM yyyy"
        return dates.prefix(12).map { e in
            "\(e.title)، \(e.kind.title)، \(Money.spoken(e.remaining))، \(e.due! < today ? "متأخر منذ" : "يستحق في") \(formatter.string(from: e.due!))"
        }.joined(separator: "\n") + (dates.count > 12 ? "\nعُرض أول ١٢ استحقاقًا." : "")
    }
    func answer(_ question: String) -> String? {
        let q = Assistant.normalize(question)
        func has(_ words: [String]) -> Bool { words.contains(where: q.contains) }
        if has(["استحقاق","يستحق","مستحق","متاخر","مواعيد"]) { return dueDebts }
        if let range = q.range(of: #"(?:لي عند|علي ل|عندي ل|مديون ل)\s*"#, options: .regularExpression) {
            let name = String(q[range.upperBound...]).trimmingCharacters(in: .punctuationCharacters.union(.whitespacesAndNewlines))
            guard !name.isEmpty else { return nil }
            let kind: EntryKind = q[range].contains("لي عند") ? .owed : .owing
            let rows = book.entries.filter { $0.kind == kind && Assistant.normalize($0.title).trimmingCharacters(in: .whitespacesAndNewlines) == name }
            guard !rows.isEmpty else { return "لم أجد دينًا بهذا الاتجاه باسم «\(name)». جرّب الاسم كما يظهر في دفتر الديون." }
            return "\(rows[0].title) · \(kind.title). أصل الديون \(Money.spoken(total(rows)))، والمدفوع \(Money.spoken(rows.reduce(0) { $0 + $1.paid }))، والمتبقي \(Money.spoken(rows.reduce(0) { $0 + $1.remaining }))."
        }
        if has(["قارن","مقارنه","تغير","الفرق"]) { return comparison }
        if has(["ميزاني","يوميا","كل يوم"]) { return budgetPlan }
        if has(["ديوني","ديون","كم علي","كم لي"]) {
            return "لك \(Money.spoken(book.totalDebt(.owed)))، وعليك \(Money.spoken(book.totalDebt(.owing))). الأرقام بعد خصم الدفعات المسجلة."
        }
        let last = has(["الماضي","السابق","الفات","اللي فات"])
        var period = last ? "الشهر السابق" : "هذا الشهر"
        var rows = expenses(last ? -1 : 0)
        if has(["اسبوع","أسبوع","اليوم","امس"]) {
            let weekly = q.contains("اسبوع")
            let component: Calendar.Component = weekly ? .weekOfYear : .day
            let prior = weekly ? last : q.contains("امس")
            let date = calendar.date(byAdding: component, value: prior ? -1 : 0, to: now) ?? now
            if let interval = calendar.dateInterval(of: component, for: date) {
                rows = book.entries.filter { $0.kind == .expense && $0.date >= interval.start && $0.date < interval.end }
                period = weekly ? (prior ? "الأسبوع السابق" : "الأسبوع الحالي") : (prior ? "أمس" : "اليوم")
            }
        }
        if has(["فئه","فئات","اكثر","اكبر","وين راح","وين راحت"]) {
            let groups = Dictionary(grouping: rows, by: \.category).mapValues(total)
            guard !groups.isEmpty else { return "لا توجد مصروفات مسجلة في \(period)." }
            return "توزيع مصروفات \(period) من الأعلى إلى الأقل:\n" + groups.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }.map { "\($0.key) · \(Money.spoken($0.value))" }.joined(separator: "\n")
        }
        if has(["صرفت","صرفي","انفقت","مصروف","مصاريف"]) {
            let category = Assistant.category(for: question, history: book.entries)
            let matching = category == "أخرى" ? rows : rows.filter { $0.category == category }
            return "إجمالي مصروفات \(period)\(category == "أخرى" ? "" : " في فئة " + category) هو \(Money.spoken(total(matching)))، عبر \(matching.count) عملية."
        }
        if has(["ملخص","وضعي","دخلي","صافي"]) && !last { return summary }
        return nil
    }
    func payoff(monthly: Int) -> String? {
        guard monthly > 0 else { return nil }
        let balance = book.totalDebt(.owing)
        guard balance > 0 else { return "لا يوجد دين قائم عليك في الدفتر." }
        let months = (balance - 1) / monthly + 1
        let final = balance - (months - 1) * monthly
        return "لرصيد \(Money.spoken(balance))، تحتاج \(months) دفعة شهرية. آخر دفعة \(Money.spoken(final)). يفترض الحساب ثبات الرصيد وعدم إضافة رسوم أو فوائد أو ديون جديدة."
    }
}
