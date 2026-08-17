import SwiftUI

struct ReviewView: View {
    @EnvironmentObject private var container: AppContainer
    @StateObject private var model = ReviewViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if model.isLoading {
                    ProgressView(L("جارٍ تجهيز المراجعة"))
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
        .task {
            await model.load(
                vocabularyRepository: container.vocabularyRepository,
                progressRepository: container.progressRepository,
                courseRepository: container.courseRepository
            )
        }
    }

    @ViewBuilder
    private var lessonReviewSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("مراجعة الدروس المجتازة"))
                        .font(.title2.bold())
                    Text(L("مراجعة ذكية قصيرة لتثبيت الذاكرة"))
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
                        .accessibilityLabel(Lf("باقي %@", "\(model.dueLessonReviews.count)"))
                }
            }

            if model.dueLessonReviews.isEmpty {
                ContentUnavailableView(
                    L("لا توجد دروس للمراجعة الآن"),
                    systemImage: "checkmark.seal.fill",
                    description: Text(L("ستظهر الدروس هنا عندما يحين وقت تثبيت ما تعلمته."))
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            } else {
                ForEach(model.dueLessonReviews.prefix(6)) { candidate in
                    NavigationLink {
                        LessonPlayerView(lesson: candidate.reviewLesson)
                    } label: {
                        lessonReviewCard(candidate)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(L("يفتح جلسة مراجعة قصيرة من هذا الدرس"))
                }
            }

            if !model.upcomingLessonReviews.isEmpty {
                DisclosureGroup(L("المراجعات القادمة")) {
                    VStack(spacing: 10) {
                        ForEach(model.upcomingLessonReviews.prefix(5)) { candidate in
                            HStack(spacing: 12) {
                                Image(systemName: "clock.arrow.circlepath")
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(displayTitle(for: candidate.lesson))
                                        .font(.subheadline.weight(.semibold))
                                    Text(Lf("بعد %@ يوم", "\(max(1, candidate.reviewIntervalDays - candidate.daysSinceCompletion))"))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("\(candidate.scorePercent)%")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .padding(.top, 8)
                }
                .font(.subheadline.weight(.semibold))
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

                Text(Lf("النتيجة السابقة %@٪", "\(candidate.scorePercent)"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text(Lf("مراجعة قصيرة %@ دقائق", "\(candidate.reviewLesson.estimatedMinutes)"))
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
        Localizer.shared.isEnglish ? lesson.titleEn : lesson.titleAr
    }
}
