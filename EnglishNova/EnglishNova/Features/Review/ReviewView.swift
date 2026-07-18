import SwiftUI

struct ReviewView: View {
    @EnvironmentObject private var container: AppContainer
    @StateObject private var model = ReviewViewModel()

    var body: some View {
        VStack(spacing: 20) {
            if model.isLoading {
                ProgressView(L("جاري تجهيز البطاقات"))
            } else if let card = model.current {
                Text("متبقي \(model.remaining)").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                VStack(spacing: 18) {
                    Text(card.word.english).font(.system(size: 44, weight: .bold, design: .rounded)).environment(\.layoutDirection, .leftToRight)
                    if let phonetic = card.word.phonetic { Text(phonetic).foregroundStyle(.secondary) }
                    VStack(spacing: 4) {
                        Text("احتمال التذكر الآن \(Int(card.estimatedRetrievability() * 100))٪")
                        Text("ثبات الذاكرة \(String(format: "%.1f", card.stabilityDays)) يوم • الانتكاسات \(card.lapses)")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityElement(children: .combine)
                    Button { container.textToSpeech.speak(card.word.english) } label: { Label(L("استمع"), systemImage: "speaker.wave.2.fill") }
                    if model.showingAnswer {
                        Divider()
                        Text(card.word.arabic).font(.title.bold())
                        Text(card.word.example).environment(\.layoutDirection, .leftToRight)
                        Text(card.word.exampleArabic).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(30)
                .background(.background, in: RoundedRectangle(cornerRadius: 24))
                .accessibilityElement(children: .contain)
                Spacer()
                if model.showingAnswer {
                    VStack(spacing: 10) {
                        Text(L("ما مدى سهولة تذكرك؟")).font(.headline)
                        Text(L("ستحدد الإجابة موعد البطاقة القادم وفق ثباتها وصعوبتها، لا بفاصل ثابت لجميع الكلمات."))
                            .font(.caption).foregroundStyle(.secondary)
                        HStack {
                            ForEach(ReviewGrade.allCases, id: \.rawValue) { grade in
                                Button(grade.titleAr) { Task { await model.grade(grade, repository: container.vocabularyRepository) } }
                                    .buttonStyle(.bordered)
                            }
                        }
                    }
                } else {
                    PrimaryButton(title: "إظهار المعنى", systemImage: "eye.fill") { model.showingAnswer = true }
                }
            } else {
                ContentUnavailableView("لا توجد مراجعات مستحقة", systemImage: "checkmark.seal.fill", description: Text(L("عُد بعد دراسة بعض الدروس أو عندما يحين موعد البطاقات.")))
            }
        }
        .padding(AppTheme.screenPadding)
        .screenBackground()
        .navigationTitle(L("المراجعة الذكية"))
        .task { await model.load(repository: container.vocabularyRepository) }
    }
}
