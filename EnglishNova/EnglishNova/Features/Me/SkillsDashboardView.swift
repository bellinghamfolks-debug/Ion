import SwiftUI

/// Six-skill dashboard with an approximate CEFR estimate.
struct SkillsDashboardView: View {
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var session: UserSession
    @State private var scores: [SkillScore] = []
    @State private var estimate: CEFREstimate?
    @State private var isLoading = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.cardSpacing) {
                if isLoading {
                    ProgressView(LE("جارٍ حساب مهاراتك", "Calculating your skills"))
                        .frame(maxWidth: .infinity, minHeight: 120)
                } else {
                    if let estimate { estimateCard(estimate) }
                    skillsCard
                    if let focus = SkillsDashboardEngine.focus(scores) { focusCard(focus) }
                }
            }
            .padding(AppTheme.screenPadding)
        }
        .screenBackground()
        .navigationTitle(LE("مهاراتي", "My skills"))
        .task { await load() }
        .refreshable { await load() }
    }

    private func estimateCard(_ estimate: CEFREstimate) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(LE("مستواك التقريبي", "Your estimated level"))
                .font(.headline)
                .foregroundStyle(.white.opacity(0.9))
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(estimate.level.rawValue)
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text(estimate.level.titleAr)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.92))
            }
            ProgressView(value: estimate.progressInLevel)
                .tint(.white)
                .accessibilityHidden(true)
            Text(confidenceText(estimate.confidence))
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.9))
            Text(LE("تقدير تقريبي من دروسك وتدريبك واختبار تحديد المستوى، وليس شهادة رسمية.",
                    "An estimate from your lessons, practice and placement test, not an official certificate."))
                .font(.caption)
                .foregroundStyle(.white.opacity(0.85))
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.heroGradient, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(LfE("مستواك التقريبي %@، %@. التقدّم نحو المستوى التالي %@ بالمئة. %@",
                                "Estimated level %@, %@. %@ percent toward the next level. %@",
                                estimate.level.rawValue, estimate.level.titleAr,
                                "\(Int((estimate.progressInLevel * 100).rounded()))", confidenceText(estimate.confidence)))
    }

    private var skillsCard: some View {
        InfoCard(title: LE("المهارات الست", "The six skills"), systemImage: "hexagon.fill", tint: AppTheme.brand) {
            ForEach(scores) { score in
                HStack(spacing: 12) {
                    Image(systemName: score.skill.systemImage)
                        .foregroundStyle(AppTheme.brand)
                        .frame(width: 28)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(score.skill.title).font(.subheadline.weight(.semibold))
                            Spacer()
                            Text(score.value.map { "\(Int(($0 * 100).rounded()))%" } ?? LE("بيانات قليلة", "Not enough data"))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        ProgressView(value: score.value ?? 0)
                            .tint(tint(for: score.value))
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(score.value.map {
                    LfE("%@: %@ بالمئة", "%@: %@ percent", score.skill.title, "\(Int(($0 * 100).rounded()))")
                } ?? LfE("%@: لا توجد بيانات كافية بعد", "%@: not enough data yet", score.skill.title))
            }
            Text(LE("تُحسب من إجاباتك في الدروس وجلسات التدريب. تظهر النسبة بعد خمس محاولات على الأقل.",
                    "Calculated from your lesson answers and practice sessions. A percentage appears after at least five attempts."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func focusCard(_ skill: DashboardSkill) -> some View {
        NavigationLink { destination(for: skill) } label: {
            InfoCard(title: LE("اقتراح للتركيز", "Suggested focus"), systemImage: "scope", tint: AppTheme.streak) {
                Text(LfE("ركّز هذا الأسبوع على %@", "Focus on %@ this week", skill.title))
                    .font(.title3.bold())
                Text(LE("افتح تدريبًا مناسبًا الآن", "Open a matching practice now"))
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.brand)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func destination(for skill: DashboardSkill) -> some View {
        switch skill {
        case .vocabulary: ReviewView()
        case .grammar: RemedialPracticeView()
        case .reading, .listening: AdvancedSkillsHubView()
        case .speaking: ShadowingCoachView()
        case .writing: WritingCoachView()
        }
    }

    private func confidenceText(_ confidence: CEFREstimate.Confidence) -> String {
        switch confidence {
        case .low: return LE("دقة التقدير: منخفضة — أكمل دروسًا أكثر أو اختبار تحديد المستوى", "Confidence: low — complete more lessons or the placement test")
        case .medium: return LE("دقة التقدير: متوسطة", "Confidence: medium")
        case .high: return LE("دقة التقدير: جيدة", "Confidence: good")
        }
    }

    private func tint(for value: Double?) -> Color {
        guard let value else { return .secondary }
        if value >= 0.8 { return AppTheme.success }
        if value >= 0.6 { return AppTheme.accentTeal }
        return AppTheme.streak
    }

    private func load() async {
        let catalog = try? await container.courseRepository.catalog()
        let progress = await container.progressRepository.snapshot()
        scores = SkillsDashboardEngine.scores(progress: progress)
        estimate = SkillsDashboardEngine.estimate(catalog: catalog, progress: progress, selectedLevel: session.selectedLevel)
        isLoading = false
    }
}
