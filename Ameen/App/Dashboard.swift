import SwiftUI

struct Dashboard: View {
    @EnvironmentObject var store: LedgerStore
    @Environment(\.calendar) private var calendar
    @Binding var settings: Bool
    @State private var month = Date()
    @State private var editor = false
    @State private var assistant = false
    var expenses: [Entry] { store.book.monthly(month, kind: .expense, calendar: calendar) }
    var spending: Int { expenses.reduce(0) { $0 + $1.amount } }
    var income: Int { store.book.monthly(month, kind: .income, calendar: calendar).reduce(0) { $0 + $1.amount } }
    var groups: [(key: String, value: Int)] {
        Dictionary(grouping: expenses, by: \.category).mapValues { $0.reduce(0) { $0 + $1.amount } }
            .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                NavigationLink { AdvisorView() } label: {
                    HStack(spacing: 14) {
                        Image("BrandMark").resizable().aspectRatio(contentMode: .fit).frame(width: 62, height: 62)
                            .clipShape(RoundedRectangle(cornerRadius: 15))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("مستشار أمين").font(.title3.bold())
                            Text("اسأل عن مصروفاتك وديونك").font(.subheadline)
                        }
                        Spacer()
                        Image(systemName: "chevron.forward").accessibilityHidden(true)
                    }.panel()
                }.accessibilityLabel("فتح مستشار أمين").accessibilityHint("شعار أمين دفتر مفتوح، ترتفع منه ثلاثة أعمدة بلون النعناع نحو نجمة ذهبية على خلفية بترولية. يفتح تحليل الدفتر والبحث في المصادر.")
                monthControl
                VStack(alignment: .leading, spacing: 12) {
                    Label("صافي الدخل بعد المصروفات", systemImage: "wallet.bifold").font(.subheadline.bold())
                    Text(Money.spoken(income - spending)).font(.largeTitle.bold()).monospacedDigit()
                    Divider().overlay(.white.opacity(0.5))
                    ViewThatFits(in: .horizontal) {
                        HStack { metric("الدخل", income); Spacer(); metric("المصروف", spending) }
                        VStack(alignment: .leading, spacing: 12) { metric("الدخل", income); metric("المصروف", spending) }
                    }
                }.foregroundStyle(.white).padding(22).frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    ZStack(alignment: .topLeading) {
                        LinearGradient(colors: [Theme.deep, Color(red: 0.02, green: 0.36, blue: 0.31)], startPoint: .topTrailing, endPoint: .bottomLeading)
                        Canvas { context, size in
                            for radius in [38, 58, 78, 98] {
                                let r = CGFloat(radius)
                                context.stroke(Path(ellipseIn: CGRect(x: -r, y: -r, width: 2*r, height: 2*r)), with: .color(.white.opacity(0.09)), lineWidth: 1.5)
                            }
                        }.accessibilityHidden(true)
                    }.clipShape(RoundedRectangle(cornerRadius: 24))
                }
                ViewThatFits(in: .horizontal) {
                    HStack { addButton; smartButton }
                    VStack(alignment: .leading) { addButton; smartButton }
                }.controlSize(.large)
                if store.book.budget > 0 {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("الميزانية الشهرية").font(.headline)
                        ProgressView(value: min(1, Double(spending) / Double(store.book.budget))).accessibilityHidden(true)
                        Text("\(spending > store.book.budget ? "تجاوزت الميزانية بمبلغ" : "المتاح للصرف") \(Money.spoken(abs(store.book.budget - spending)))")
                    }.panel()
                }
                VStack(alignment: .leading, spacing: 12) {
                    Text("توزيع المصروفات").font(.title3.bold()).accessibilityAddTraits(.isHeader)
                    if groups.isEmpty { Text("سيظهر هنا توزيع مصروفات الشهر بعد أول عملية.").foregroundStyle(.secondary) }
                    ForEach(groups, id: \.key) { item in
                        VStack(alignment: .leading) {
                            Text("\(item.key) · \(Money.spoken(item.value))")
                            ProgressView(value: Double(item.value) / Double(max(spending, 1))).accessibilityHidden(true)
                        }.accessibilityElement(children: .ignore).accessibilityLabel("\(item.key)، \(Money.spoken(item.value))، \(Int((100 * Double(item.value) / Double(max(spending, 1))).rounded())) بالمئة من إجمالي المصروفات")
                    }
                }.panel()
                VStack(alignment: .leading, spacing: 8) {
                    Text("الديون القائمة").font(.title3.bold()).accessibilityAddTraits(.isHeader)
                    metric("لي عند الآخرين", store.book.totalDebt(.owed))
                    Divider()
                    metric("عليّ للآخرين", store.book.totalDebt(.owing))
                }.panel()
            }.padding()
        }.background(Color(uiColor: .systemGroupedBackground)).navigationTitle("أمين")
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { settings = true } label: { Image(systemName: "gearshape") }.accessibilityLabel("الإعدادات والنسخ الاحتياطي") } }
        .sheet(isPresented: $editor) { NavigationStack { EntryEditor() } }
        .sheet(isPresented: $assistant) { NavigationStack { AssistantView() } }
    }
    var addButton: some View { Button { editor = true } label: { Label("إضافة حركة", systemImage: "plus") }.buttonStyle(.borderedProminent) }
    var smartButton: some View { Button { assistant = true } label: { Label("مساعد أمين", systemImage: "sparkles") }.buttonStyle(.bordered) }
    func metric(_ title: String, _ value: Int) -> some View {
        VStack(alignment: .leading, spacing: 3) { Text(title).font(.caption); Text(Money.spoken(value)).font(.headline) }.accessibilityElement(children: .combine)
    }
    var monthControl: some View {
        HStack {
            Button { moveMonth(-1) } label: { Image(systemName: "minus.circle") }.accessibilityLabel("الشهر السابق").frame(minWidth: 44, minHeight: 44)
            Spacer()
            Text(monthTitle).font(.headline)
            Spacer()
            Button { moveMonth(1) } label: { Image(systemName: "plus.circle") }.accessibilityLabel("الشهر التالي").frame(minWidth: 44, minHeight: 44)
        }
    }
    var monthTitle: String {
        let f = DateFormatter()
        f.locale = Money.locale
        f.calendar = calendar
        f.dateFormat = "MMMM yyyy"
        return f.string(from: month)
    }
    func moveMonth(_ n: Int) { month = calendar.date(byAdding: .month, value: n, to: month) ?? month }
}
extension View {
    func panel() -> some View { padding(18).frame(maxWidth: .infinity, alignment: .leading).background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20)) }
}
