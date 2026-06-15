import SwiftUI

@MainActor
final class LearningPathwaysViewModel: ObservableObject {
    @Published var snapshot = UserProgressSnapshot()
    @Published var isLoading = true

    func load(container: AppContainer) async {
        isLoading = true
        snapshot = await container.progressRepository.snapshot()
        isLoading = false
    }
}

struct LearningPathwaysView: View {
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var settings: AppSettings
    @StateObject private var model = LearningPathwaysViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("اختر وجهتك").font(.largeTitle.bold())
                Text("المسار لا يقفل المحتوى. إنه يغيّر الأولويات ويحوّل الجلسات المسجلة إلى مراحل قابلة للقياس.")
                    .foregroundStyle(.secondary)

                ForEach(LearningPathwayCatalog.all) { pathway in
                    pathwayCard(pathway)
                }
            }
            .padding(AppTheme.screenPadding)
        }
        .screenBackground()
        .navigationTitle("مسارات التعلّم")
        .task { await model.load(container: container) }
        .refreshable { await model.load(container: container) }
    }

    private func pathwayCard(_ pathway: LearningPathwayDefinition) -> some View {
        let progress = LearningPathwayCatalog.progress(for: pathway.id, snapshot: model.snapshot)
        let selected = settings.selectedLearningPathway == pathway.id
        return InfoCard(title: pathway.titleAr, systemImage: pathway.id.systemImage) {
            Text(pathway.detailAr).foregroundStyle(.secondary)
            HStack {
                Label("الهدف \(pathway.targetLevel.rawValue)", systemImage: "scope")
                Spacer()
                Label("نحو \(pathway.estimatedWeeks) أسبوعًا", systemImage: "calendar")
            }
            .font(.caption)
            AccessibleProgressView(
                title: "\(progress.completedMilestones) من \(progress.totalMilestones) مراحل",
                value: progress.overallProgress
            )
            if let current = progress.currentMilestone {
                VStack(alignment: .leading, spacing: 5) {
                    Text("المرحلة الحالية: \(current.titleAr)").font(.headline)
                    Text(current.detailAr).font(.caption).foregroundStyle(.secondary)
                    AccessibleProgressView(title: "تقدم المرحلة \(Int(progress.currentMilestoneProgress * 100))٪", value: progress.currentMilestoneProgress)
                }
            } else if progress.completedMilestones == progress.totalMilestones {
                Label("اكتملت مراحل المسار المسجلة", systemImage: "checkmark.seal.fill")
            }
            Button(selected ? "المسار المحدد" : "اختيار هذا المسار") {
                settings.selectedLearningPathway = pathway.id
                settings.studyMode = suggestedMode(for: pathway.id)
            }
            .buttonStyle(.borderedProminent)
            .disabled(selected)
            .accessibilityHint(selected ? "هذا هو المسار الحالي" : "يضبط أولويات الخطة اليومية ولا يحذف تقدمك")

            DisclosureGroup("مراحل المسار") {
                ForEach(Array(pathway.milestones.enumerated()), id: \.element.id) { index, milestone in
                    HStack(alignment: .top) {
                        Image(systemName: index < progress.completedMilestones ? "checkmark.circle.fill" : "circle")
                            .accessibilityHidden(true)
                        VStack(alignment: .leading) {
                            Text(milestone.titleAr).font(.subheadline.bold())
                            Text("\(milestone.requiredSessions) جلسة، متوسط \(Int(milestone.requiredAverageScore * 100))٪")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func suggestedMode(for pathway: LearningPathwayID) -> StudyMode {
        switch pathway {
        case .foundations: return .balanced
        case .dailyFluency: return .conversation
        case .academicIELTS, .stepMastery: return .exam
        case .careerEnglish, .legalGovernance: return .career
        }
    }
}
