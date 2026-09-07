import SwiftUI

@MainActor
final class IELTSBandSixViewModel: ObservableObject {
    @Published var blocks: [IELTSStudyBlock] = []
    @Published var readiness: IELTSReadinessSnapshot?
    @Published var todayMinutes = 0
    @Published var isLoading = true

    func load(container: AppContainer, level: CEFRLevel, targetMinutes: Int) async {
        isLoading = true
        let progress = await container.progressRepository.snapshot()
        let due = await container.vocabularyRepository.dueCards(on: .now)
        var planned = IELTSBandSixEngine.dailyBlocks(
            level: level,
            progress: progress,
            dueCardCount: due.count
        )
        let effectiveTarget = IELTSBandSixEngine.effectiveDailyTarget(configuredMinutes: targetMinutes)
        if effectiveTarget > IELTSBandSixEngine.minimumDailyMinutes, let last = planned.indices.last {
            let item = planned[last]
            planned[last] = IELTSStudyBlock(
                id: item.id,
                area: item.area,
                titleAr: item.titleAr,
                detailAr: item.detailAr,
                minutes: item.minutes + effectiveTarget - IELTSBandSixEngine.minimumDailyMinutes,
                breakAfterMinutes: item.breakAfterMinutes
            )
        }
        blocks = planned
        readiness = IELTSBandSixEngine.readiness(level: level, progress: progress)
        todayMinutes = progress.activity
            .filter { Calendar.current.isDateInToday($0.date) }
            .reduce(0) { $0 + max(0, $1.minutes) }
        isLoading = false
    }
}

struct IELTSBandSixView: View {
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var session: UserSession
    @EnvironmentObject private var settings: AppSettings
    @StateObject private var model = IELTSBandSixViewModel()

    private var targetMinutes: Int { settings.effectiveDailyGoalMinutes }
    private var dailyProgress: Double {
        min(1, Double(model.todayMinutes) / Double(max(1, targetMinutes)))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                if settings.selectedLearningPathway != .academicIELTS {
                    activationCard
                }
                if model.isLoading {
                    ProgressView(L("جارٍ بناء خطة IELTS اليوم"))
                        .frame(maxWidth: .infinity, minHeight: 80)
                } else {
                    progressCard
                    dailyBlocks
                    readinessCard
                    scoreGuide
                    roadmap
                }
            }
            .padding(AppTheme.screenPadding)
        }
        .screenBackground()
        .navigationTitle("IELTS 6.0")
        .navigationBarTitleDisplayMode(.inline)
        .task { await reload() }
        .refreshable { await reload() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("منهج IELTS Academic إلى Band 6.0"))
                .font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader)
            Text(L("مسار متدرج من مستواك الحالي، بثلاث ساعات يوميًا على الأقل. الدرجة المعروضة مؤشر تدريبي محافظ وليست نتيجة IELTS رسمية."))
                .foregroundStyle(.secondary)
        }
    }

    private var activationCard: some View {
        InfoCard(title: L("فعّل المسار الجاد"), systemImage: "scope") {
            Text(L("سيضبط الهدف اليومي على 180 دقيقة على الأقل، وستة أيام أسبوعيًا، ويوقف وضع الخطة المختصرة."))
            PrimaryButton(title: L("اختيار مسار IELTS 6.0"), systemImage: "checkmark.seal.fill") {
                settings.selectLearningPathway(.academicIELTS)
                Task { await reload() }
            }
        }
    }

    private var progressCard: some View {
        let remaining = max(0, targetMinutes - model.todayMinutes)
        return InfoCard(title: L("تقدم اليوم المقيس"), systemImage: "clock.badge.checkmark") {
            AccessibleProgressView(
                title: Lf("%@ من %@ دقيقة", "\(min(model.todayMinutes, targetMinutes))", "\(targetMinutes)"),
                value: dailyProgress
            )
            Text(remaining == 0
                 ? L("أكملت الحد اليومي. راجع خطأ واحدًا فقط إذا أردت نشاطًا إضافيًا.")
                 : Lf("متبقي %@ دقيقة. لا تُحتسب مشاهدة الخطة؛ تُحتسب الأنشطة المسجلة فقط.", "\(remaining)"))
                .font(.subheadline)
            if let readiness = model.readiness {
                Label(
                    Lf("مرحلتك الحالية: %@", "\(readiness.phase.titleAr)"),
                    systemImage: "flag.fill"
                )
                Text(readiness.phase.detailAr).font(.caption).foregroundStyle(.secondary)
                Text(Lf("المدة الإرشادية المتبقية عند الالتزام: نحو %@ أسبوعًا.", "\(readiness.phase.expectedRemainingWeeks)"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var dailyBlocks: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("خطة اليوم: 180 دقيقة على الأقل"))
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
            ForEach(Array(model.blocks.enumerated()), id: \.element.id) { index, block in
                destinationLink(for: block, number: index + 1)
            }
            Text(L("الاستراحات خارج وقت الدراسة: خذ خمس دقائق بعد كل كتلة، ولا تخصمها من 180 دقيقة."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func destinationLink(for block: IELTSStudyBlock, number: Int) -> some View {
        let card = InfoCard(title: "\(number). \(L(block.titleAr))", systemImage: block.area.systemImage) {
            Text(L(block.detailAr)).foregroundStyle(.secondary)
            Label(Lf("%@ دقيقة دراسة", "\(block.minutes)"), systemImage: "timer")
            if block.breakAfterMinutes > 0 {
                Text(Lf("بعدها استراحة اختيارية %@ دقائق.", "\(block.breakAfterMinutes)"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        switch block.area {
        case .course:
            NavigationLink { CurriculumView() } label: { card }.buttonStyle(.plain)
        case .vocabulary:
            NavigationLink { ReviewView() } label: { card }.buttonStyle(.plain)
        case .listening:
            NavigationLink { IELTSObjectivePracticeView(section: .listening) } label: { card }.buttonStyle(.plain)
        case .reading:
            NavigationLink { IELTSObjectivePracticeView(section: .reading) } label: { card }.buttonStyle(.plain)
        case .writing:
            NavigationLink { IELTSWritingPracticeView() } label: { card }.buttonStyle(.plain)
        case .speaking:
            NavigationLink { IELTSSpeakingSimulatorView() } label: { card }.buttonStyle(.plain)
        case .correction:
            NavigationLink { MistakeNotebookView() } label: { card }.buttonStyle(.plain)
        case .mock:
            NavigationLink { IELTSObjectiveMockRecorderView() } label: { card }.buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var readinessCard: some View {
        if let readiness = model.readiness {
            InfoCard(
                title: readiness.isReadyForBandSix ? L("جاهزية Band 6 مستقرة") : L("مؤشر الجاهزية المحافظ"),
                systemImage: readiness.isReadyForBandSix ? "checkmark.seal.fill" : "chart.bar.fill"
            ) {
                if let overall = readiness.overallBand {
                    Text(Lf("التقدير العام التدريبي: %@", "\(bandText(overall))"))
                        .font(.title2.bold())
                } else {
                    Text(L("لا توجد أدلة كافية لعرض رقم عام بعد."))
                        .font(.headline)
                }
                ForEach(readiness.sectionEstimates) { estimate in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Label(estimate.section.titleAr, systemImage: estimate.section.systemImage)
                            Spacer()
                            Text(estimate.estimatedBand.map { bandText($0) } ?? L("غير مقاس"))
                                .monospacedDigit()
                        }
                        Text(Lf("%@ جلسات مقيسة • ثقة %@٪", "\(estimate.evidenceCount)", "\(Int(estimate.confidence * 100))"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
                if !readiness.blockersAr.isEmpty {
                    Divider()
                    Text(L("ما يمنع إعلان الجاهزية الآن")).font(.headline)
                    ForEach(readiness.blockersAr, id: \.self) { item in
                        Label(item, systemImage: "arrow.up.right.circle")
                    }
                }
                Text(L("يحتاج المؤشر أربع جلسات حديثة على الأقل لكل قسم، في يومين مختلفين، ويشترط 5.5 على الأقل في كل قسم مع متوسط 6.0."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var scoreGuide: some View {
        InfoCard(title: L("قياس أقرب إلى الاختبار"), systemImage: "doc.text.magnifyingglass") {
            Text(L("بعد حل نموذج كامل، سجّل عدد الإجابات الصحيحة من 40. يستهدف Band 6 عادةً قرابة 23 في Listening وAcademic Reading، وقد تختلف الحدود قليلًا بين النماذج."))
            NavigationLink { IELTSObjectivePracticeView(section: .listening) } label: {
                Label(L("تدريب Listening: أربع وحدات و40 سؤالًا"), systemImage: "headphones")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: 48)
            }
            NavigationLink { IELTSObjectivePracticeView(section: .reading) } label: {
                Label(L("تدريب Academic Reading: أربع وحدات و40 سؤالًا"), systemImage: "book.pages.fill")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: 48)
            }
            NavigationLink { IELTSObjectiveMockRecorderView() } label: {
                Label(L("سجل نتيجة محاكاة كاملة"), systemImage: "square.and.pencil")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: 48)
            }
            NavigationLink { PlacementTestView(startingLevel: session.selectedLevel) } label: {
                Label(L("أعد اختبار تحديد المستوى"), systemImage: "scope")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: 48)
            }
        }
    }

    private var roadmap: some View {
        InfoCard(title: L("خارطة 36 أسبوعًا"), systemImage: "map.fill") {
            Text(L("الخارطة مبنية على 180 دقيقة في اليوم وستة أيام في الأسبوع. المدة تتغير بحسب نتيجة تحديد المستوى وثبات الأداء."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            ForEach(IELTSBandSixEngine.roadmap) { stage in
                DisclosureGroup("\(L(stage.weekRangeAr)): \(L(stage.titleAr))") {
                    Text(L(stage.outcomeAr))
                    Label(L(stage.checkpointAr), systemImage: "checkmark.circle")
                        .font(.caption)
                }
            }
        }
    }

    private func reload() async {
        await model.load(container: container, level: session.selectedLevel, targetMinutes: settings.dailyGoalMinutes)
    }

    private func bandText(_ value: Double) -> String {
        String(format: "%.1f", value)
    }
}

struct IELTSWritingPracticeView: View {
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var session: UserSession
    @State private var taskIndex = 0
    @State private var draft = ""
    @State private var evaluation: IELTSWritingEvaluation?
    @State private var startedAt = Date()
    @State private var savedTaskID: String?

    private var task: IELTSWritingTask {
        IELTSBandSixEngine.writingTasks[taskIndex % IELTSBandSixEngine.writingTasks.count]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(task.type.titleAr).font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
                Text(Lf("الوقت المستهدف %@ دقيقة • الحد الأدنى %@ كلمة", "\(task.type.recommendedMinutes)", "\(task.type.minimumWords)"))
                    .foregroundStyle(.secondary)

                InfoCard(title: L("السؤال"), systemImage: "doc.text.fill") {
                    Text(task.prompt)
                        .environment(\.layoutDirection, .leftToRight)
                        .textSelection(.enabled)
                    if let description = task.accessibleSourceDescription {
                        Divider()
                        Text(L("وصف نصي كامل للبيانات")).font(.headline)
                        Text(description)
                            .environment(\.layoutDirection, .leftToRight)
                            .textSelection(.enabled)
                        Text(L("هذا الوصف النصي هو مصدر البيانات المعتمد للمهمة، ولا توجد صورة مطلوبة لفهمها."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                InfoCard(title: L("قائمة فحص المهمة"), systemImage: "checklist") {
                    ForEach(task.checklistAr, id: \.self) { item in
                        Label(L(item), systemImage: "checkmark.circle")
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(L("إجابتك باللغة الإنجليزية")).font(.title2.bold())
                    TextEditor(text: $draft)
                        .frame(minHeight: 300)
                        .padding(8)
                        .background(.background, in: RoundedRectangle(cornerRadius: 14))
                        .environment(\.layoutDirection, .leftToRight)
                        .accessibilityLabel(L("حقل إجابة IELTS Writing"))
                        .accessibilityHint(L("اكتب نصًا مترابطًا بفقرات كاملة، وليس نقاطًا مختصرة."))
                    Text(Lf("%@ كلمة", "\(wordCount)"))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(wordCount >= task.type.minimumWords ? Color.secondary : Color.orange)
                }

                PrimaryButton(title: L("حلل بالمعايير الأربعة"), systemImage: "text.magnifyingglass") {
                    analyze()
                }
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if let evaluation {
                    evaluationCard(evaluation)
                    Button(L("المهمة التالية")) { nextTask() }
                        .buttonStyle(.borderedProminent)
                        .frame(minHeight: 48)
                }
            }
            .padding(AppTheme.screenPadding)
        }
        .screenBackground()
        .navigationTitle("IELTS Writing")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var wordCount: Int {
        draft.split { !$0.isLetter && !$0.isNumber && $0 != "'" }.count
    }

    private func evaluationCard(_ value: IELTSWritingEvaluation) -> some View {
        InfoCard(title: L("تقييم محلي محافظ"), systemImage: "chart.bar.doc.horizontal.fill") {
            Text(Lf("Band تدريبي تقريبي: %@", "\(String(format: "%.1f", value.estimatedBand))"))
                .font(.title2.bold())
            criterion(L("إنجاز المهمة أو الاستجابة"), value.taskResponse)
            criterion(L("الترابط والتماسك"), value.coherenceAndCohesion)
            criterion(L("الثروة المعجمية"), value.lexicalResource)
            criterion(L("تنوع القواعد ودقتها"), value.grammaticalRangeAndAccuracy)
            Divider()
            Text(L("نقاط القوة")).font(.headline)
            ForEach(value.strengthsAr, id: \.self) { Label($0, systemImage: "checkmark.circle.fill") }
            Text(L("التعديل التالي")).font(.headline)
            ForEach(value.improvementsAr, id: \.self) { Label($0, systemImage: "arrow.up.right.circle.fill") }
            Text(L(value.limitationsAr)).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func criterion(_ title: String, _ value: Double) -> some View {
        AccessibleProgressView(title: "\(title) \(Int(value * 100))٪", value: value)
    }

    private func analyze() {
        let value = IELTSBandSixEngine.evaluateWriting(text: draft, task: task)
        evaluation = value
        guard savedTaskID != task.id else { return }
        savedTaskID = task.id
        let elapsed = max(1, Int(Date().timeIntervalSince(startedAt) / 60))
        let measuredMinutes = min(task.type.recommendedMinutes, elapsed)
        Task {
            await container.progressRepository.recordPracticeSession(.init(
                id: UUID().uuidString,
                domain: .writing,
                sourceID: task.id,
                titleAr: task.type.titleAr,
                level: session.selectedLevel,
                score: IELTSBandSixEngine.practicePerformance(forEstimatedBand: value.estimatedBand),
                minutes: measuredMinutes,
                createdAt: .now,
                details: value.improvementsAr
            ))
        }
    }

    private func nextTask() {
        taskIndex = (taskIndex + 1) % IELTSBandSixEngine.writingTasks.count
        draft = ""
        evaluation = nil
        savedTaskID = nil
        startedAt = .now
    }
}

struct IELTSObjectiveMockRecorderView: View {
    @EnvironmentObject private var container: AppContainer
    @State private var listeningCorrect = 23
    @State private var readingCorrect = 23
    @State private var didSave = false

    var body: some View {
        Form {
            Section {
                Text(L("استخدم هذه الشاشة بعد إنهاء محاكاة كاملة من 40 سؤالًا لكل قسم. لا تسجل نتيجة تدريب قصير؛ لأن ذلك سيرفع مؤشر الجاهزية بشكل مضلل."))
                    .foregroundStyle(.secondary)
            }
            Section(L("Listening")) {
                Stepper(Lf("الإجابات الصحيحة: %@ من 40", "\(listeningCorrect)"), value: $listeningCorrect, in: 0...40)
                LabeledContent(L("Band التدريبي"), value: String(format: "%.1f", IELTSBandSixEngine.objectiveBand(correct: listeningCorrect, section: .listening)))
            }
            Section(L("Academic Reading")) {
                Stepper(Lf("الإجابات الصحيحة: %@ من 40", "\(readingCorrect)"), value: $readingCorrect, in: 0...40)
                LabeledContent(L("Band التدريبي"), value: String(format: "%.1f", IELTSBandSixEngine.objectiveBand(correct: readingCorrect, section: .reading)))
            }
            Section {
                Button {
                    Task { await save() }
                } label: {
                    Label(didSave ? L("حُفظت نتيجة اليوم") : L("حفظ نتيجتي المحاكاة"), systemImage: didSave ? "checkmark.circle.fill" : "square.and.arrow.down")
                }
                .disabled(didSave)
                Text(L("التحويل تقريبي لأن الحد الدقيق قد يختلف قليلًا بين نسخ الاختبار. في المتوسط، 23 من 40 يقابل Band 6 في Listening وAcademic Reading."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(L("نتيجة المحاكاة الكاملة"))
    }

    private func save() async {
        let day = Int(Date().startOfDay.timeIntervalSince1970)
        await container.progressRepository.recordPracticeSession(.init(
            id: "ielts-full-listening-\(day)",
            domain: .listening,
            sourceID: "ielts-full-listening",
            titleAr: "IELTS Listening 40",
            level: .b2,
            score: Double(listeningCorrect) / 40,
            minutes: 40,
            createdAt: .now,
            details: ["\(listeningCorrect)/40", "Band \(IELTSBandSixEngine.objectiveBand(correct: listeningCorrect, section: .listening))"]
        ))
        await container.progressRepository.recordPracticeSession(.init(
            id: "ielts-full-reading-\(day)",
            domain: .reading,
            sourceID: "ielts-full-reading",
            titleAr: "IELTS Academic Reading 40",
            level: .b2,
            score: Double(readingCorrect) / 40,
            minutes: 60,
            createdAt: .now,
            details: ["\(readingCorrect)/40", "Band \(IELTSBandSixEngine.objectiveBand(correct: readingCorrect, section: .reading))"]
        ))
        didSave = true
        ToastCenter.shared.show(L("حُفظت نتيجة المحاكاة"), style: .success)
    }
}
