import SwiftUI

@main struct AmeenApp: App {
    @StateObject private var store = LedgerStore()
    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(store)
                .environment(\.layoutDirection, .rightToLeft)
                .environment(\.locale, Locale(identifier: "ar_SA"))
                .environment(\.calendar, Calendar(identifier: .gregorian))
        }
    }
}
enum Theme {
    static let teal = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.37, green: 0.89, blue: 0.75, alpha: 1) : UIColor(red: 0.01, green: 0.36, blue: 0.31, alpha: 1) })
    static let deep = Color(red: 0.035, green: 0.19, blue: 0.19)
}
struct RootView: View {
    @EnvironmentObject var store: LedgerStore
    @State private var settings = false
    var body: some View {
        TabView {
            NavigationStack { Dashboard(settings: $settings) }.tabItem { Label("الرئيسية", systemImage: "square.grid.2x2") }
            NavigationStack { RegisterView(debts: false) }.tabItem { Label("الحركات", systemImage: "list.bullet.rectangle") }
            NavigationStack { RegisterView(debts: true) }.tabItem { Label("الديون", systemImage: "person.2") }
            NavigationStack { AdvisorView() }.tabItem { Label("المستشار", systemImage: "sparkles") }
        }.tint(Theme.teal)
        .safeAreaInset(edge: .top, spacing: 0) {
            if let error = store.loadError {
                VStack {
                    Text(error)
                    HStack { Button("إعادة المحاولة") { store.reload() }; Button("الإعدادات") { settings = true } }
                }.padding().background(.regularMaterial)
            }
        }.sheet(isPresented: $settings) { NavigationStack { SettingsView() } }
    }
}
struct EntryRow: View {
    let entry: Entry
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { symbol; description; Spacer(); amount }
            VStack(alignment: .leading, spacing: 8) { description; amount }
        }.padding(.vertical, 5).accessibilityElement(children: .ignore)
        .accessibilityLabel("\(entry.kind.title)، \(entry.title)، \(entry.kind.isDebt ? "المتبقي" : "المبلغ") \(Money.spoken(entry.kind.isDebt ? entry.remaining : entry.amount))، \(day(entry.date))")
    }
    var symbol: some View {
        Image(systemName: entry.kind.icon).frame(width: 39, height: 39)
            .foregroundStyle(Theme.teal).background(Theme.teal.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
            .accessibilityHidden(true)
    }
    var description: some View {
        VStack(alignment: .leading) { Text(entry.title).font(.headline); Text("\(entry.kind.title) · \(day(entry.date))").font(.caption).foregroundStyle(.secondary) }
    }
    var amount: some View {
        Text(Money.spoken(entry.kind.isDebt ? entry.remaining : entry.amount)).font(.subheadline.bold()).monospacedDigit()
    }
}
func day(_ date: Date) -> String {
    let f = DateFormatter()
    f.locale = Money.locale
    f.calendar = Calendar(identifier: .gregorian)
    f.dateFormat = "d MMMM yyyy"
    return f.string(from: date)
}
struct EmptyMessage: View {
    let title: String
    let hint: String
    var body: some View {
        VStack(alignment: .leading, spacing: 5) { Text(title).font(.headline); Text(hint).foregroundStyle(.secondary) }
            .padding(.vertical, 8).accessibilityElement(children: .combine)
    }
}
