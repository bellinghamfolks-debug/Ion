import SwiftUI
import UIKit

struct GlossaryView: View {
    var highlighted: GlossaryTerm?

    var body: some View {
        ProForm(title: L("screen.glossary")) {
            ForEach(GlossaryTerm.allCases) { term in
                VStack(alignment: .leading, spacing: 4) {
                    Text(term.title).font(.headline).accessibilityAddTraits(.isHeader)
                    Text(term.body).font(.body)
                }
                .padding(.vertical, 4)
                .listRowBackground(term == highlighted ? Theme.surfaceRaised : nil)
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// Six short lessons, each followed by two questions.
struct AcademyView: View {
    @Environment(AppModel.self) var model

    var body: some View {
        let done = Set(model.data.life.pro.lessonsDone)
        ProForm(title: L("screen.academy")) {
            Section {
                ForEach(AcademyLesson.allCases) { lesson in
                    NavigationLink { LessonView(lesson: lesson) } label: {
                        HStack {
                            Text(lesson.title)
                            Spacer()
                            if done.contains(lesson.rawValue) {
                                Image(systemName: "checkmark.seal.fill").foregroundStyle(Theme.success).accessibilityLabel(L("academy.done"))
                            }
                        }
                    }
                }
            } footer: { Text(L("academy.progress", done.count, AcademyLesson.allCases.count)) }
        }
    }
}

struct LessonView: View {
    @Environment(AppModel.self) var model
    let lesson: AcademyLesson
    @State var answers: [String: String] = [:]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(Array(lesson.paragraphs.enumerated()), id: \.offset) { _, paragraph in
                    Text(paragraph).font(.body).fixedSize(horizontal: false, vertical: true)
                }
                ForEach(lesson.questions) { question in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(question.prompt).font(.headline).accessibilityAddTraits(.isHeader)
                        ForEach(question.shuffled, id: \.self) { choice in
                            let picked = answers[question.id] == choice
                            Button {
                                answers[question.id] = choice
                                let right = choice == question.correct
                                if right { Announcer.shared.success() } else { Announcer.shared.warning() }
                                Announcer.shared.announce(right ? L("academy.right") : L("academy.wrong", question.correct), priority: .high)
                                finishIfDone()
                            } label: {
                                HStack {
                                    Text(choice).foregroundStyle(Theme.textPrimary)
                                    Spacer()
                                    if picked { Image(systemName: choice == question.correct ? "checkmark.circle.fill" : "xmark.circle.fill").accessibilityHidden(true) }
                                }
                                .padding(12)
                                .card()
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(picked ? .isSelected : [])
                        }
                    }
                }
            }
            .padding(20)
        }
        .screenBackground()
        .navigationTitle(lesson.title)
    }

    private func finishIfDone() {
        let all = lesson.questions
        guard all.allSatisfy({ answers[$0.id] == $0.correct }), !model.data.life.pro.lessonsDone.contains(lesson.rawValue) else { return }
        model.updateData { data in
            data.life.pro.lessonsDone.append(lesson.rawValue)
            data.life.pro.quizBest = max(data.life.pro.quizBest, data.life.pro.lessonsDone.count)
        }
        Announcer.shared.announce(L("academy.lessonDone", lesson.title))
    }
}

/// Shown once after updating to a new version.
struct WhatsNewView: View {
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(Array(WhatsNew.items.enumerated()), id: \.offset) { _, item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title).font(.headline).accessibilityAddTraits(.isHeader)
                            Text(item.body).font(.body).foregroundStyle(Theme.textSecondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                    Button(L("whatsNew.continue")) { dismiss() }.buttonStyle(PrimaryButtonStyle())
                }
                .padding(20)
            }
            .screenBackground()
            .navigationTitle(L("screen.whatsNew"))
        }
    }
}

/// A problem report with what the app knows, sent by the person through
/// any app they choose (mail, messages). Nothing is sent automatically.
struct ReportProblemView: View {
    @Environment(AppModel.self) var model
    @State var description = ""

    var body: some View {
        let report = text()
        ProForm(title: L("screen.report")) {
            Section {
                TextField(L("reportProblem.placeholder"), text: $description, axis: .vertical).lineLimit(3...8)
            } header: { Text(L("reportProblem.what")) }
            Section {
                ShareLink(item: report) { Label(L("reportProblem.share"), systemImage: "paperplane") }
                Text(report).font(.footnote.monospaced()).textSelection(.enabled)
            } footer: { Text(L("reportProblem.footer")) }
        }
    }

    private func text() -> String {
        let device = UIDevice.current
        let recent = model.data.life.pro.alarmHistory.prefix(5).map { "\($0.alarm.rawValue) \($0.date.formatted(.iso8601))" }
        return [
            L("reportProblem.header"),
            description,
            "",
            "App: \(AppVersion.full)",
            "iOS: \(device.systemVersion) (\(device.model))",
            "Link: \(model.settings.linkKind.rawValue), \(model.connection.isConnected ? "connected" : "not connected")",
            "Machine: \(model.data.life.activeMachine?.model ?? "-")",
            "Power: \(model.snapshot.power.rawValue), alarms: \(model.snapshot.alarms.map(\.rawValue).joined(separator: ","))",
            "RSSI: \(model.snapshot.rssi.map(String.init) ?? "-")",
            "Recent alarms: \(recent.joined(separator: "; "))",
            "Bluetooth packets seen: \(model.traffic.count)",
        ].joined(separator: "\n")
    }
}

/// Find anything: drinks, favorites, beans, care guides, words and screens.
struct GlobalSearchView: View {
    @Environment(AppModel.self) var model
    @State var query = ""
    @State var pendingBrew: Recipe?

    var body: some View {
        let hits = GlobalSearch.search(query, data: model.data)
        List {
            if query.count >= 2, hits.isEmpty { Text(L("search.nothing")).foregroundStyle(Theme.textSecondary) }
            ForEach(hits) { hit in
                NavigationLink { destination(hit.target) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(hit.title).font(.headline)
                        Text(hit.subtitle).font(.footnote).foregroundStyle(Theme.textSecondary)
                    }
                }
            }
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: L("globalSearch.prompt"))
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(L("globalSearch.title"))
        .onChange(of: hits.count) { _, count in
            if query.count >= 2 { Announcer.shared.announce(L("search.results", count)) }
        }
    }

    @ViewBuilder
    private func destination(_ target: SearchHit.Target) -> some View {
        switch target {
        case .drink(let beverage): DrinkDetailView(route: .beverage(beverage), initial: model.initialRecipe(for: .beverage(beverage)))
        case .favorite(let recipe): DrinkDetailView(route: .favorite(recipe), initial: recipe.normalized())
        case .bean: BeansView()
        case .guide(let guide): GuideView(guide: guide)
        case .glossary(let term): GlossaryView(highlighted: term)
        case .signature(let id): SignatureRecipeView(recipeID: id)
        case .screen(let screen): ProScreenView(screen: screen)
        }
    }
}

/// Opens any version 3 screen by name (search, hubs).
struct ProScreenView: View {
    let screen: ProScreen

    var body: some View {
        switch screen {
        case .cups: CupsView()
        case .organizer: FavoritesOrganizerView()
        case .combos: CombosView()
        case .teaTimer: TeaTimerView()
        case .voPractice: VoiceOverPracticeView()
        case .purchases: PurchasesView()
        case .compareBeans: CompareBeansView()
        case .alarmHistory: AlarmHistoryView()
        case .serviceReport: ServiceReportView()
        case .travel: TravelChecklistView()
        case .supplies: SuppliesView()
        case .profileNames: ProfileNamesView()
        case .touchGuide: TouchscreenGuideView()
        case .cupCheck: CupCheckView()
        case .guestMenu: GuestMenuView()
        case .hosting: HostingPlannerView()
        case .office: OfficeTallyView()
        case .monthly: MonthlyReportView()
        case .hourly: HourlyChartView()
        case .reduction: CaffeineView()
        case .backup: BackupView()
        case .historyEditor: HistoryEditorView()
        case .privacy: PrivacyDashboardView()
        case .glossary: GlossaryView()
        case .academy: AcademyView()
        case .whatsNew: WhatsNewView()
        case .report: ReportProblemView()
        case .accessibility3: AccessibilityPlusView()
        case .children: ChildProfilesView()
        case .milk: MilkAndWaterView()
        }
    }
}

/// A list of links to version 3 screens, used in Settings and the Machine tab.
struct ProLinks: View {
    struct Link: Identifiable {
        let screen: ProScreen
        let symbol: String
        var id: ProScreen { screen }
    }

    let links: [Link]

    init(_ pairs: [(ProScreen, String)]) {
        links = pairs.map { Link(screen: $0.0, symbol: $0.1) }
    }

    var body: some View {
        ForEach(links) { link in
            NavigationLink { ProScreenView(screen: link.screen) } label: { Label(link.screen.title, systemImage: link.symbol) }
        }
    }
}
