import SwiftUI

struct ReviewView: View {
    @EnvironmentObject private var container: AppContainer
    @StateObject private var model = ReviewViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if model.isLoading {
                    ProgressView(LE("جارٍ تجهيز المراجعة", "Preparing review"))
                        .padding(.vertical, 40)
                } else {
                    lessonReviewSection
                    wordReviewSection
                }
            }
            .padding(AppTheme.screenPadding)
        }
        .screenBackground()
        .navigationTitle(L("المراجعة"))
        .onAppear {
            Task { await reload() }
        }
    }

    @ViewBuilder
    private var lessonReviewSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(LE("مراجعة الدروس المجتازة", "Review completed lessons"))
                        .font(.title2.bold())
                    Text(LE(
                        "جلسات قصيرة متباعدة لتثبيت ما تعلمته",
                        "Short spaced sessions to strengthen retention"
                    ))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                if !model.dueLessonReviews.isEmpty {
                    Text("\(model.dueLessonReviews.count)")
                        .font(.headline.monospacedDigit())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.thinMaterial, in: Capsule())
                        .accessibilityLabel(LfE(
                            "%@ مراجعات مستحقة",
                            "%@ reviews due",
                            "\(model.dueLessonReviews.count)"
                        ))
                }
            }

            if model.lessonReviews.isEmpty {
                ContentUnavailableView(
                    LE("لا توجد دروس مجتازة بعد", "No completed lessons yet"),
                    systemImage: "books.vertical",
                    description: Text(LE(
                        "بعد اجتياز أول درس سيبدأ التطبيق بجدولة مراجعات قصيرة تلقائيًا.",
                        "After you pass your first lesson, the app will automatically schedule short reviews."
                    ))
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            } else if model.dueLessonReviews.isEmpty {
                ContentUnavailableView(
                    LE("لا توجد دروس للمراجعة الآن", "No lesson reviews due now"),
                    systemImage: "checkmark.seal.fill",
                    description: Text(LE(
                        "جدول التكرار المتباعد سيعيد الدروس عندما يحين الوقت المناسب للتثبيت.",
                        "Spaced review will bring lessons back when reinforcement is most useful."
                    ))
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            } else {
                ForEach(model.dueLessonReviews.prefix(6)) { candidate in
                    NavigationLink {
                        LessonReviewSessionView(candidate: candidate)
                    } label: {
                        lessonReviewCard(candidate)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(LE(
                        "يفتح جلسة مراجعة قصيرة من تمارين هذا الدرس.",
                        "Opens a short review session using exercises from this lesson."
                    ))
                }
            }

            if !model.upcomingLessonReviews.isEmpty {
                DisclosureGroup(LE("المراجعات القادمة", "Upcoming reviews")) {
                    VStack(spacing: 10) {
                        ForEach(model.upcomingLessonReviews.prefix(5)) { candidate in
                            NavigationLink {
                                LessonReviewSessionView(candidate: candidate)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "clock.arrow.circlepath")
                                        .accessibilityHidden(true)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(displayTitle(for: candidate.lesson))
                                            .font(.subheadline.weight(.semibold))
                                        Text(dueText(candidate))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text("\(scorePercent(candidate))%")
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                    Image(systemName: "chevron.forward")
                                        .font(.caption.bold())
                                        .foregroundStyle(.tertiary)
                                        .accessibilityHidden(true)
                                }
                                .padding(.vertical, 4)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 8)
                }
                .font(.subheadline.weight(.semibold))
            }

            if !model.lessonReviews.isEmpty {
                NavigationLink {
                    CompletedLessonReviewListView()
                } label: {
                    Label(LE("عرض كل الدروس المجتازة", "View all completed lessons"), systemImage: "list.bullet")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.background, in: RoundedRectangle(cornerRadius: 24))
    }

    private func lessonReviewCard(_ candidate: LessonReviewCandidate) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                .font(.title2)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text(displayTitle(for: candidate.lesson))
                    .font(.headline)
                    .multilineTextAlignment(.leading)

                Text(LfE(
                    "أفضل نتيجة في الدرس %@٪",
                    "Lesson best %@%",
                    "\(scorePercent(candidate))"
                ))
                .font(.subheadline)
                .foregroundStyle(.secondary)

                Text(LfE(
                    "مراجعة قصيرة، نحو %@ دقائق",
                    "Short review, about %@ min",
                    "\(reviewMinutes(candidate))"
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()
            Image(systemName: "chevron.forward")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var wordReviewSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L("مراجعة الكلمات"))
                .font(.title2.bold())

            if let card = model.current {
                Text(Lf("باقي %@", "\(model.remaining)"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                VStack(spacing: 18) {
                    Text(card.word.english)
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .environment(\.layoutDirection, .leftToRight)

                    if let phonetic = card.word.phonetic {
                        Text(phonetic).foregroundStyle(.secondary)
                    }

                    Button {
                        container.textToSpeech.speak(card.word.english)
                    } label: {
                        Label(L("سماع الكلمة"), systemImage: "speaker.wave.2.fill")
                    }

                    if model.showingAnswer {
                        Divider()
                        Text(L(card.word.arabic)).font(.title.bold())
                        Text(card.word.example)
                            .environment(\.layoutDirection, .leftToRight)
                        Text(L(card.word.exampleArabic))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(24)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
                .accessibilityElement(children: .contain)

                if model.showingAnswer {
                    VStack(spacing: 10) {
                        Text(L("كيف كان تذكرك للكلمة؟"))
                            .font(.headline)
                        Text(L("اختر التقييم الأقرب لما حدث فعلًا؛ سيستخدمه التطبيق لتحديد موعد المراجعة التالية."))
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack {
                            ForEach(ReviewGrade.allCases, id: \.rawValue) { grade in
                                Button(grade.titleAr) {
                                    Task {
                                        await model.grade(grade, repository: container.vocabularyRepository)
                                    }
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                } else {
                    PrimaryButton(title: L("إظهار المعنى"), systemImage: "eye.fill") {
                        model.showingAnswer = true
                    }
                }
            } else {
                ContentUnavailableView(
                    L("لا توجد كلمات للمراجعة الآن"),
                    systemImage: "checkmark.seal.fill",
                    description: Text(L("ستظهر هنا الكلمات عندما يحين موعد مراجعتها."))
                )
                .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.background, in: RoundedRectangle(cornerRadius: 24))
    }

    private func displayTitle(for lesson: Lesson) -> String {
        LE(lesson.titleAr, lesson.titleEn)
    }

    private func scorePercent(_ candidate: LessonReviewCandidate) -> Int {
        Int((candidate.progress.bestScore * 100).rounded())
    }

    private func reviewMinutes(_ candidate: LessonReviewCandidate) -> Int {
        let count = LessonReviewEngine.reviewExercises(
            for: candidate.lesson,
            reviewCount: candidate.state?.repetitions ?? 0
        ).count
        return max(3, min(8, count))
    }

    private func dueText(_ candidate: LessonReviewCandidate) -> String {
        if candidate.isDue { return LE("مستحقة الآن", "Due now") }
        let days = max(
            1,
            Calendar.current.dateComponents(
                [.day],
                from: Date().startOfDay,
                to: candidate.dueDate.startOfDay
            ).day ?? 1
        )
        if days == 1 { return LE("المراجعة غدًا", "Review tomorrow") }
        return LfE("بعد %@ أيام", "In %@ days", "\(days)")
    }

    private func reload() async {
        await model.load(
            vocabularyRepository: container.vocabularyRepository,
            progressRepository: container.progressRepository,
            courseRepository: container.courseRepository
        )
    }
}
