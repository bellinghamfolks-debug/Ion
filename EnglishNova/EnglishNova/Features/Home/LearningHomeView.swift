import SwiftUI

/// The "Today" tab: one clear daily session instead of a wall of cards.
struct LearningHomeView: View {
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var session: UserSession
    @EnvironmentObject private var settings: AppSettings
    @StateObject private var model = HomeViewModel()
    @ObservedObject private var store = DailySessionStore.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.cardSpacing) {
                welcome
                if model.isLoading && model.catalog == nil {
                    ProgressView(LE("جارٍ تجهيز جلسة اليوم", "Preparing today's session"))
                        .frame(maxWidth: .infinity, minHeight: 120)
                } else {
                    sessionHero
                    stepsList
                    wordOfTheDay
                }
                aiLearningBrief
                progressSummary
            }
            .padding(AppTheme.screenPadding)
        }
        .screenBackground()
        .navigationTitle(LE("اليوم", "Today"))
        .refreshable { await model.load(container: container) }
        .onAppear {
            store.reload()
            Task { await model.load(container: container) }
        }
        .onChange(of: dailySession.steps.map(\.kind)) { _, kinds in
            store.markPlanned(kinds)
        }
        .alert(L("تعذر تحديث الصفحة"), isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button(L("حسنًا")) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var dailySession: DailySession {
        model.dailySession(level: session.selectedLevel, store: store, goalMinutes: settings.dailyGoalMinutes)
    }

    private var greetingName: String {
        let local = session.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !local.isEmpty { return local }
        return container.accountService.currentUser?.displayName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(greetingName.isEmpty ? L("مرحبًا") : Lf("مرحبًا، %@", greetingName))
                .font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader)
            // At large text sizes the chips stack instead of clipping.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { statChips }
                VStack(alignment: .leading, spacing: 8) { statChips }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var statChips: some View {
        StatChip(systemImage: "flame.fill", tint: AppTheme.streak,
                 value: "\(session.streak)", label: LE("أيام متتالية", "day streak"))
        if session.streakFreezes > 0 {
            StatChip(systemImage: "snowflake", tint: AppTheme.accentTeal,
                     value: "\(session.streakFreezes)", label: LE("حماية للسلسلة", "streak freeze"))
        }
        StatChip(systemImage: "star.fill", tint: AppTheme.warning,
                 value: "\(session.points)", label: LE("نقطة", "points"))
        StatChip(systemImage: "graduationcap.fill", tint: AppTheme.brand,
                 value: session.selectedLevel.rawValue, label: LE("المستوى", "level"))
    }

    // MARK: - Session

    @ViewBuilder
    private var sessionHero: some View {
        let value = dailySession
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 16) {
                ZStack {
                    Circle().stroke(.white.opacity(0.25), lineWidth: 8)
                    Circle()
                        .trim(from: 0, to: value.progress)
                        .stroke(.white, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(value.completedCount)/\(value.steps.count)")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(.white)
                }
                .frame(width: 64, height: 64)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(LE("جلسة اليوم", "Today's session"))
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                        .accessibilityAddTraits(.isHeader)
                    Text(value.isComplete
                         ? LE("أنهيت جلسة اليوم. أحسنت!", "You finished today's session. Well done!")
                         : LfE("%@ من %@ خطوات • قرابة %@ دقيقة متبقية", "%@ of %@ steps • about %@ min left",
                               "\(value.completedCount)", "\(value.steps.count)", "\(value.remainingMinutes)"))
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.92))
                }
            }
            .accessibilityElement(children: .combine)

            if value.isComplete {
                HStack {
                    Spacer()
                    CelebrationView(systemImage: "trophy.fill", tint: .white, size: 70)
                    Spacer()
                }
                Text(LE("يمكنك متابعة درس إضافي من «المسار» أو التدرّب بحرية من «التدريب».",
                        "Continue with an extra lesson from Path, or practise freely in Practice."))
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.92))
            } else if let next = value.nextStep {
                NavigationLink { destination(for: next.kind) } label: {
                    Label(value.completedCount == 0 ? LE("ابدأ الجلسة", "Start session") : LE("تابع الجلسة", "Continue session"),
                          systemImage: "play.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: AppTheme.minimumTapHeight)
                        .foregroundStyle(AppTheme.brand)
                        .background(.white, in: RoundedRectangle(cornerRadius: AppTheme.compactCornerRadius, style: .continuous))
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityHint(LfE("الخطوة التالية: %@", "Next step: %@", title(for: next)))
            }
        }
        .padding(20)
        .background(AppTheme.heroGradient, in: RoundedRectangle(cornerRadius: AppTheme.cornerRadius, style: .continuous))
    }

    private var stepsList: some View {
        VStack(spacing: 10) {
            ForEach(Array(dailySession.steps.enumerated()), id: \.element.id) { index, step in
                NavigationLink { destination(for: step.kind) } label: {
                    stepRow(step, number: index + 1)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func stepRow(_ step: DailyStep, number: Int) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(step.isDone ? AppTheme.success : tint(for: step.kind).opacity(0.15))
                Image(systemName: step.isDone ? "checkmark" : icon(for: step.kind))
                    .font(.headline)
                    .foregroundStyle(step.isDone ? .white : tint(for: step.kind))
            }
            .frame(width: 44, height: 44)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(title(for: step))
                    .font(.headline)
                    .strikethrough(step.isDone, color: .secondary)
                Text(detail(for: step))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            Text(LfE("%@ د", "%@ min", "\(step.minutes)"))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Image(systemName: "chevron.forward")
                .font(.caption.bold())
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(14)
        .background(AppTheme.cardSurface, in: RoundedRectangle(cornerRadius: AppTheme.compactCornerRadius, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(LfE("الخطوة %@: %@. %@. قرابة %@ دقيقة.", "Step %@: %@. %@. About %@ minutes.",
                                "\(number)", title(for: step), detail(for: step), "\(step.minutes)"))
        .accessibilityValue(step.isDone ? LE("مكتملة", "Done") : LE("لم تكتمل", "Not done"))
        .accessibilityAddTraits(.isButton)
    }

    private func title(for step: DailyStep) -> String {
        switch step.kind {
        case .review: return LE("مراجعة سريعة", "Quick review")
        case .lesson: return step.isDone ? LE("درس اليوم مكتمل", "Today's lesson done") : LE("الدرس التالي", "Next lesson")
        case .mistakes: return LE("تدرّب على أخطائك", "Practise your mistakes")
        case .speaking: return LE("تحدّث دقيقتين", "Speak for two minutes")
        }
    }

    private func detail(for step: DailyStep) -> String {
        switch step.kind {
        case .review:
            return step.count > 0 ? LfE("%@ عناصر حان وقت مراجعتها", "%@ items due for review", "\(step.count)")
                                  : LE("لا مراجعات متبقية اليوم", "No reviews left today")
        case .lesson:
            if let lesson = model.nextLesson(for: session.selectedLevel) { return LE(lesson.titleAr, lesson.titleEn) }
            return LE("تابع منهجك", "Continue your course")
        case .mistakes:
            return step.count > 0 ? LfE("%@ أسئلة أخطأت فيها سابقًا", "%@ items you missed before", "\(step.count)")
                                  : LE("لا أخطاء مفتوحة", "No open mistakes")
        case .speaking:
            return LE("قل جملة من درسك واحصل على ملاحظات على نطقك", "Say a sentence from your lesson and get pronunciation feedback")
        }
    }

    private func icon(for kind: DailyStepKind) -> String {
        switch kind {
        case .review: return "rectangle.stack.fill"
        case .lesson: return "play.fill"
        case .mistakes: return "arrow.uturn.backward"
        case .speaking: return "waveform.and.mic"
        }
    }

    private func tint(for kind: DailyStepKind) -> Color {
        switch kind {
        case .review: return AppTheme.accentTeal
        case .lesson: return AppTheme.brand
        case .mistakes: return AppTheme.streak
        case .speaking: return AppTheme.brandSecondary
        }
    }

    @ViewBuilder
    private func destination(for kind: DailyStepKind) -> some View {
        switch kind {
        case .review:
            ReviewView()
        case .lesson:
            if let lesson = model.nextLesson(for: session.selectedLevel) {
                LessonPlayerView(lesson: lesson)
            } else {
                CurriculumView()
            }
        case .mistakes:
            RemedialPracticeView(onFinish: { store.markDone(.mistakes) })
        case .speaking:
            PronunciationLabView(initialTarget: model.speakingSentence(for: session.selectedLevel),
                                 onComplete: { store.markDone(.speaking) })
        }
    }

    // MARK: - Secondary cards

    @ViewBuilder
    private var wordOfTheDay: some View {
        if let word = DailyContentEngine.wordOfTheDay(catalog: model.catalog, level: session.selectedLevel) {
            InfoCard(title: LE("كلمة اليوم", "Word of the day"), systemImage: "sparkle", tint: AppTheme.warning) {
                HStack(alignment: .firstTextBaseline) {
                    Text(word.english)
                        .font(.title.bold())
                        .environment(\.layoutDirection, .leftToRight)
                    if let phonetic = word.phonetic, !phonetic.isEmpty {
                        Text(phonetic).font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        container.textToSpeech.speak(word.english)
                    } label: {
                        Image(systemName: "speaker.wave.2.fill").font(.title3)
                    }
                    .accessibilityLabel(LfE("استمع إلى %@", "Listen to %@", word.english))
                }
                Text(word.arabic).font(.headline)
                if !word.example.isEmpty {
                    Text(word.example)
                        .environment(\.layoutDirection, .leftToRight)
                        .foregroundStyle(.secondary)
                }
                Button {
                    Task { await container.vocabularyRepository.add(words: [word]) }
                    ToastCenter.shared.show(LfE("أُضيفت «%@» إلى مراجعتك", "Added “%@” to your review", word.english))
                } label: {
                    Label(LE("أضفها إلى مراجعتي", "Add to my review"), systemImage: "plus.circle")
                }
                .buttonStyle(.bordered)
            }
        }
    }

    @ViewBuilder
    private var aiLearningBrief: some View {
        if let brief = model.aiBrief {
            InfoCard(title: L("اقتراح المدرب"), systemImage: "brain.head.profile", tint: AppTheme.accentTeal) {
                Text(brief.headlineAr)
                    .font(.title3.bold())
                    .accessibilityAddTraits(.isHeader)
                if !brief.focusAr.isEmpty {
                    Text(brief.focusAr).font(.headline)
                }
                if !brief.whyAr.isEmpty {
                    Text(brief.whyAr).foregroundStyle(.secondary)
                }
                ForEach(brief.actionsAr, id: \.self) { action in
                    Label(action, systemImage: "checkmark.circle")
                        .font(.subheadline)
                }
                if !brief.challengeEn.isEmpty {
                    Divider()
                    Text(L("تطبيق قصير"))
                        .font(.caption.bold())
                    Text(brief.challengeEn)
                        .environment(\.layoutDirection, .leftToRight)
                        .textSelection(.enabled)
                }
                NavigationLink { AIExerciseView(startAdaptive: true) } label: {
                    Label(L("أنشئ تدريبًا يناسب احتياجي"), systemImage: "wand.and.stars")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(minHeight: 48)
                }
                .accessibilityHint(L("ينشئ تدريبًا جديدًا بناءً على أخطائك ونتائجك الأخيرة"))
            }
        } else if model.isLoadingAIBrief && container.accountService.isAuthenticated {
            ProgressView(L("جارٍ إعداد اقتراح المدرب"))
                .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        }
    }

    private var progressSummary: some View {
        let goal = max(1, settings.dailyGoalMinutes)
        return InfoCard(title: L("تقدّمك اليوم"), systemImage: "chart.line.uptrend.xyaxis", tint: AppTheme.success) {
            AccessibleProgressView(
                title: Lf("%@ من %@ دقيقة", "\(model.todayMinutes)", "\(goal)"),
                value: min(1, Double(model.todayMinutes) / Double(goal))
            )
            if let insights = model.insights {
                HStack(spacing: 12) {
                    metric(value: "\(insights.completedLessons)", label: L("الدروس المكتملة"))
                    metric(value: "\(insights.activeDaysLast30)", label: L("أيام الدراسة خلال 30 يومًا"))
                }
            }
            NavigationLink { WeeklyProgressReportView() } label: {
                Label(L("التقرير الأسبوعي"), systemImage: "doc.text.image")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: 44)
            }
        }
    }

    private func metric(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title3.bold()).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}

/// Compact pill showing one number (streak, points, level).
struct StatChip: View {
    let systemImage: String
    let tint: Color
    let value: String
    let label: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(value).font(.subheadline.bold()).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(AppTheme.cardSurface, in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(value) \(label)")
    }
}
