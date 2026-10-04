import SwiftUI

/// The "Me" tab: your review, your progress, and your settings in one place.
struct MeView: View {
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var session: UserSession
    @EnvironmentObject private var account: AccountService
    @State private var openMistakes = 0
    @State private var dueWords = 0

    var body: some View {
        List {
            Section { header }

            Section(LE("مراجعتي", "My review")) {
                NavigationLink { ReviewView() } label: {
                    row(LE("المراجعة", "Review"), detail: dueWords > 0 ? LfE("%@ كلمة مستحقة", "%@ words due", "\(dueWords)") : LE("الدروس والكلمات", "Lessons and words"),
                        systemImage: "arrow.triangle.2.circlepath", tint: AppTheme.accentTeal)
                }
                NavigationLink { RemedialPracticeView() } label: {
                    row(LE("تدرّب على أخطائك", "Practise your mistakes"),
                        detail: openMistakes > 0 ? LfE("%@ أخطاء مفتوحة", "%@ open mistakes", "\(openMistakes)") : LE("لا أخطاء مفتوحة", "No open mistakes"),
                        systemImage: "arrow.uturn.backward.circle.fill", tint: AppTheme.streak)
                }
                NavigationLink { MistakeNotebookView() } label: {
                    row(L("دفتر الأخطاء"), detail: LE("كل ملاحظاتك في مكان واحد", "All your notes in one place"),
                        systemImage: "exclamationmark.bubble.fill", tint: AppTheme.streak)
                }
                NavigationLink { WordbookView() } label: {
                    row(L("دفتر المفردات"), detail: LE("الكلمات التي تعلمتها", "Words you have learned"),
                        systemImage: "character.book.closed.fill", tint: AppTheme.brand)
                }
            }

            Section(LE("تقدّمي", "My progress")) {
                NavigationLink { SkillsDashboardView() } label: {
                    row(LE("مهاراتي ومستواي", "My skills and level"), detail: LE("المهارات الست وتقدير مستواك", "Six skills and your estimated level"),
                        systemImage: "hexagon.fill", tint: AppTheme.brand)
                }
                NavigationLink { LearningInsightsView() } label: {
                    row(L("تحليل التقدّم"), detail: LE("مهاراتك ونقاط قوتك", "Your skills and strengths"),
                        systemImage: "chart.xyaxis.line", tint: AppTheme.success)
                }
                NavigationLink { WeeklyProgressReportView() } label: {
                    row(L("التقرير الأسبوعي"), detail: LE("ملخص أسبوعك", "Your week at a glance"),
                        systemImage: "doc.text.image.fill", tint: AppTheme.success)
                }
                NavigationLink { AchievementsView() } label: {
                    row(L("الإنجازات"), detail: LE("الأوسمة التي حصلت عليها", "Badges you have earned"),
                        systemImage: "trophy.fill", tint: AppTheme.warning)
                }
                NavigationLink { LeagueView() } label: {
                    row(LE("الدوري الأسبوعي", "Weekly league"), detail: LE("نافس متعلّمين في مستواك هذا الأسبوع", "Compete with learners in your tier this week"),
                        systemImage: "trophy.circle.fill", tint: AppTheme.streak)
                }
                NavigationLink { LeaderboardView() } label: {
                    row(L("الترتيب"), detail: LE("قارن نقاطك", "Compare your points"),
                        systemImage: "list.number", tint: AppTheme.warning)
                }
            }

            Section(LE("الحساب والإعدادات", "Account and settings")) {
                NavigationLink { AccountView() } label: {
                    row(account.isAuthenticated ? LE("حسابي", "My account") : LE("تسجيل الدخول", "Sign in"),
                        detail: account.isAuthenticated ? LE("المزامنة والملف الشخصي", "Sync and profile") : LE("احفظ تقدّمك على كل أجهزتك", "Keep your progress on all your devices"),
                        systemImage: "person.crop.circle.fill", tint: AppTheme.brand)
                }
                NavigationLink { SettingsView() } label: {
                    row(L("الإعدادات"), detail: LE("اللغة والتذكير والصوت والخصوصية", "Language, reminders, audio and privacy"),
                        systemImage: "gearshape.fill", tint: .gray)
                }
            }
        }
        .navigationTitle(LE("أنا", "Me"))
        .task { await load() }
        .refreshable { await load() }
    }

    private var displayName: String {
        let local = session.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !local.isEmpty { return local }
        return account.currentUser?.displayName ?? ""
    }

    private var header: some View {
        HStack(spacing: 16) {
            Text(initials)
                .font(.title2.bold())
                .foregroundStyle(.white)
                .frame(width: 64, height: 64)
                .background(AppTheme.brandGradient, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(displayName.isEmpty ? LE("متعلّم EnglishNova", "EnglishNova learner") : displayName)
                    .font(.title3.bold())
                    .accessibilityAddTraits(.isHeader)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { chips }
                    VStack(alignment: .leading, spacing: 6) { chips }
                }
            }
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var chips: some View {
        StatChip(systemImage: "flame.fill", tint: AppTheme.streak, value: "\(session.streak)", label: LE("أيام", "days"))
        StatChip(systemImage: "star.fill", tint: AppTheme.warning, value: "\(session.points)", label: LE("نقطة", "pts"))
        StatChip(systemImage: "graduationcap.fill", tint: AppTheme.brand, value: session.selectedLevel.rawValue, label: "")
    }

    private var initials: String {
        let letters = displayName.split(separator: " ").prefix(2).compactMap(\.first)
        return letters.isEmpty ? "EN" : String(letters).uppercased()
    }

    private func row(_ title: String, detail: String, systemImage: String, tint: Color) -> some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.headline)
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(tint.opacity(0.13), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private func load() async {
        async let memory = container.learningMemoryRepository.snapshot()
        async let due = container.vocabularyRepository.dueCards(on: .now)
        let catalog = try? await container.courseRepository.catalog()
        let loadedMemory = await memory
        let loadedDue = await due
        openMistakes = RemedialPracticeEngine.items(mistakes: loadedMemory.mistakes, catalog: catalog, limit: 99).count
        dueWords = loadedDue.count
    }
}
