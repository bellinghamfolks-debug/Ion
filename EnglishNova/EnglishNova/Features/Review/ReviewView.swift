import SwiftUI

struct ReviewView: View {
    @EnvironmentObject private var container: AppContainer
    @StateObject private var model = ReviewViewModel()

    var body: some View {
        VStack(spacing: 20) {
            if model.isLoading {
                ProgressView(L("جارٍ تجهيز المراجعة"))
            } else if let card = model.current {
                Text(Lf("باقي %@", "\(model.remaining)"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()

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
                .padding(30)
                .background(.background, in: RoundedRectangle(cornerRadius: 24))
                .accessibilityElement(children: .contain)

                Spacer()

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
            }
        }
        .padding(AppTheme.screenPadding)
        .screenBackground()
        .navigationTitle(L("المراجعة"))
        .task { await model.load(repository: container.vocabularyRepository) }
    }
}
