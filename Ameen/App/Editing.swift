import SwiftUI

struct EntryEditor: View {
    @EnvironmentObject var store: LedgerStore
    @Environment(\.dismiss) private var dismiss
    let original: Entry?
    @State var kind: EntryKind
    @State var name: String
    @State var amount: String
    @State var category: String
    @State var date: Date
    @State var hasDue: Bool
    @State var due: Date
    @State var error: String?
    init(original: Entry? = nil, initialKind: EntryKind = .expense, draft: Assistant.Draft? = nil) {
        self.original = original
        _kind = State(initialValue: original?.kind ?? draft?.kind ?? initialKind)
        _name = State(initialValue: original?.title ?? draft?.title ?? "")
        _amount = State(initialValue: original.map { Money.input($0.amount) } ?? draft?.amount ?? "")
        _category = State(initialValue: original?.category ?? draft?.category ?? "أخرى")
        _date = State(initialValue: original?.date ?? draft?.date ?? .now)
        _hasDue = State(initialValue: original?.due != nil)
        _due = State(initialValue: original?.due ?? original?.date ?? .now)
    }
    var body: some View {
        Form {
            Section {
                Picker("نوع العملية", selection: $kind) { ForEach(EntryKind.allCases) { Text($0.title).tag($0) } }.disabled(original?.payments.isEmpty == false)
                TextField(kind.isDebt ? "اسم الشخص أو الجهة" : "وصف العملية", text: $name).accessibilityLabel(kind.isDebt ? "اسم الشخص أو الجهة" : "وصف العملية")
                TextField("المبلغ بالريال", text: $amount).keyboardType(.decimalPad).accessibilityLabel("المبلغ بالريال")
                if kind == .expense { Picker("الفئة", selection: $category) { ForEach(Assistant.categories, id: \.self) { Text($0) } } }
                DatePicker("تاريخ التسجيل", selection: $date, in: ...Date.now, displayedComponents: .date)
                if kind.isDebt {
                    Toggle("تحديد موعد استحقاق", isOn: $hasDue)
                    if hasDue { DatePicker("تاريخ الاستحقاق", selection: $due, in: Calendar.current.startOfDay(for: date)..., displayedComponents: .date) }
                }
            }
            if let error { Text(error).foregroundStyle(.red).accessibilityLabel("خطأ. " + error) }
            Button("حفظ العملية", action: save)
        }.navigationTitle(original == nil ? "عملية جديدة" : "تعديل العملية")
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("إلغاء") { dismiss() } } }
    }
    func save() {
        guard let value = Money.parse(amount) else { fail("أدخل مبلغًا موجبًا بدقة هللتين كحد أقصى."); return }
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean.count <= 160 else { fail("أدخل وصفًا أو اسمًا من حرف إلى ١٦٠ حرفًا."); return }
        let cal = Calendar.current
        let day = cal.startOfDay(for: date)
        var e = Entry(kind: kind, title: clean, amount: value, date: day, category: kind == .expense ? category : "أخرى", due: kind.isDebt && hasDue ? cal.startOfDay(for: due) : nil)
        if let original { e.id = original.id; e.payments = original.payments }
        do {
            try store.update { book in
                if let index = book.entries.firstIndex(where: { $0.id == e.id }) { book.entries[index] = e }
                else { book.entries.append(e) }
            }
            dismiss()
            Feedback.saved("تم حفظ \(kind.title) بمبلغ \(Money.spoken(value))")
        } catch { fail(error.localizedDescription) }
    }
    func fail(_ message: String) { error = message; UIAccessibility.post(notification: .announcement, argument: message) }
}
struct AssistantView: View {
    @EnvironmentObject var store: LedgerStore
    @Environment(\.dismiss) var dismiss
    @State var text = ""
    @State var error: String?
    @State var draft: Assistant.Draft?
    var body: some View {
        Group {
            if let draft { EntryEditor(draft: draft) }
            else {
                Form {
                    Section("اكتب العملية أو استخدم إملاء لوحة المفاتيح") {
                        TextField("دفعت ٣٥ ريال للقهوة", text: $text, axis: .vertical).lineLimit(2...5).accessibilityLabel("عبارة العملية")
                        Button("مراجعة اقتراح أمين") {
                            do { draft = try Assistant.draft(text, history: store.book.entries) }
                            catch { self.error = error.localizedDescription; UIAccessibility.post(notification: .announcement, argument: error.localizedDescription) }
                        }
                        if let error { Text(error).foregroundStyle(.red) }
                    }
                    Section("جرّب مثالًا") {
                        ForEach(["دفعت ٣٥ ريال للقهوة", "استلمت راتب ٨٠٠٠ ريال", "استلفت من خالد ٥٠٠ ريال", "أقرضت سارة ٢٠٠ ريال"], id: \.self) { phrase in Button(phrase) { text = phrase; error = nil } }
                    }
                }.navigationTitle("مساعد أمين")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("إغلاق") { dismiss() } } }
            }
        }
    }
}
