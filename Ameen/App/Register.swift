import SwiftUI

struct RegisterView: View {
    @EnvironmentObject var store: LedgerStore
    let debts: Bool
    @State var query = ""
    @State var filter: EntryKind?
    @State var editor = false
    var items: [Entry] {
        store.book.entries.reversed().filter {
            $0.kind.isDebt == debts && (filter == nil || $0.kind == filter) &&
            (query.isEmpty || Assistant.normalize($0.title + " " + $0.category).contains(Assistant.normalize(query)))
        }.sorted { $0.date > $1.date }
    }
    var body: some View {
        List {
            Picker("عرض", selection: $filter) {
                Text("الكل").tag(nil as EntryKind?)
                ForEach(EntryKind.allCases.filter { $0.isDebt == debts }) { Text($0.title).tag(Optional($0)) }
            }.pickerStyle(.segmented)
            if items.isEmpty {
                EmptyMessage(title: query.isEmpty ? "السجل فارغ" : "لا توجد نتائج", hint: query.isEmpty ? "استخدم زر الإضافة لتسجيل أول عملية." : "جرّب اسمًا أو وصفًا آخر.")
            }
            ForEach(items) { e in NavigationLink { DetailView(id: e.id) } label: { EntryRow(entry: e) } }
        }.navigationTitle(debts ? "الديون" : "الحركات")
        .searchable(text: $query, prompt: "بحث بالاسم أو الوصف")
        .toolbar { ToolbarItem(placement: .primaryAction) { Button { editor = true } label: { Image(systemName: "plus") }.accessibilityLabel(debts ? "إضافة دين" : "إضافة حركة") } }
        .sheet(isPresented: $editor) { NavigationStack { EntryEditor(initialKind: filter ?? (debts ? .owing : .expense)) } }
    }
}
struct DetailView: View {
    let id: UUID
    @EnvironmentObject var store: LedgerStore
    @Environment(\.dismiss) var dismiss
    @State var editing = false
    @State var deleting = false
    @State var payment = ""
    @State var error: String?
    var body: some View {
        if let e = store.book.entries.first(where: { $0.id == id }) {
            Form {
                Section(e.kind.title) {
                    Text(e.title).font(.title2.bold()).accessibilityAddTraits(.isHeader)
                    LabeledContent("المبلغ", value: Money.spoken(e.amount))
                    LabeledContent("تاريخ التسجيل", value: day(e.date))
                    if e.kind == .expense { LabeledContent("الفئة", value: e.category) }
                    if let due = e.due { LabeledContent("الاستحقاق", value: day(due)) }
                }
                if e.kind.isDebt {
                    Section("حالة الدين") {
                        LabeledContent("المدفوع", value: Money.spoken(e.paid))
                        LabeledContent("المتبقي", value: Money.spoken(e.remaining))
                        if e.remaining == 0 { Label("تم السداد بالكامل", systemImage: "checkmark.circle") }
                        else {
                            TextField("مبلغ الدفعة بالريال", text: $payment).keyboardType(.decimalPad).accessibilityLabel("مبلغ الدفعة بالريال")
                            Button(e.kind == .owing ? "تسجيل دفعة سددتها" : "تسجيل دفعة استلمتها") {
                                do {
                                    guard let value = Money.parse(payment) else { throw BookError.payment }
                                    try store.update { try $0.pay(id: id, amount: value, date: .now) }
                                    payment = ""; error = nil
                                    Feedback.saved("سُجلت الدفعة. المتبقي \(Money.spoken(e.remaining - value))", payment: true)
                                } catch { self.error = error.localizedDescription; UIAccessibility.post(notification: .announcement, argument: error.localizedDescription) }
                            }
                        }
                    }
                    if !e.payments.isEmpty {
                        Section("سجل السداد") { ForEach(e.payments.reversed()) { p in LabeledContent(day(p.date), value: Money.spoken(p.amount)) } }
                    }
                }
                if let error { Text(error).foregroundStyle(.red) }
                Button("تعديل العملية") { editing = true }
                Button("حذف العملية", role: .destructive) { deleting = true }
            }.navigationTitle("تفاصيل العملية")
            .sheet(isPresented: $editing) { NavigationStack { EntryEditor(original: e) } }
            .confirmationDialog("حذف العملية وجميع دفعاتها؟", isPresented: $deleting, titleVisibility: .visible) {
                Button("حذف نهائي", role: .destructive) {
                    do { try store.update { $0.entries.removeAll { $0.id == id } }; dismiss(); Feedback.saved("تم حذف العملية") }
                    catch { self.error = error.localizedDescription }
                }
            }
        }
    }
}
