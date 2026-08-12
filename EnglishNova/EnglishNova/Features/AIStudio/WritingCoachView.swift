import SwiftUI

/// Server-AI writing coach. Rich feedback is written back into the learner's
/// progress and mistake memory, so future tutoring can target recurring issues.
struct WritingCoachView: View {
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var session: UserSession
    @State private var text = ""
    @State private var result: WritingResult?
    @State private var loading = false
    @State private var errorMessage: String?

    private let service = AIStudioService()

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                InfoCard(title: L("مدرب الكتابة الذكي"), systemImage: "pencil.and.scribble") {
                    Text(L("اكتب جملة أو فقرة بالإنجليزية. سيصححها المدرب وفق مستواك، يشرح أهم الأخطاء، ثم يستخدم النتيجة لتحسين تدريبك القادم."))
                        .font(.footnote).foregroundStyle(.secondary)

                    TextEditor(text: $text)
                        .frame(minHeight: 130)
                        .environment(\.layoutDirection, .leftToRight)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))

                    PrimaryButton(title: L("حلل كتابتي"), systemImage: "checkmark.seal.fill", isLoading: loading,
                                  isDisabled: trimmed.isEmpty) { run() }
                }

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote).foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let result {
                    if let score = result.score {
                        InfoCard(title: L("التقييم"), systemImage: "gauge.with.dots.needle.67percent",
                                 tint: AppTheme.accentTeal) {
                            AccessibleProgressView(title: L("جودة الكتابة"), value: Double(score) / 100)
                            LabeledContent(L("الدرجة"), value: "\(score)/100")
                        }
                    }

                    InfoCard(title: L("النص المصحح"), systemImage: "text.badge.checkmark", tint: AppTheme.success) {
                        Text(result.corrected)
                            .font(.body.weight(.medium))
                            .environment(\.layoutDirection, .leftToRight)
                            .textSelection(.enabled)
                    }

                    InfoCard(title: L("تحليل المدرب"), systemImage: "brain.head.profile", tint: AppTheme.warning) {
                        Text(result.feedbackAr)
                        if !result.strengthsAr.isEmpty {
                            Divider()
                            Text(L("نقاط جيدة"))
                                .font(.headline)
                            ForEach(result.strengthsAr, id: \.self) { item in
                                Label(item, systemImage: "checkmark.circle.fill")
                            }
                        }
                        if !result.improvementsAr.isEmpty {
                            Divider()
                            Text(L("الأولوية التالية"))
                                .font(.headline)
                            ForEach(result.improvementsAr, id: \.self) { item in
                                Label(item, systemImage: "arrow.up.circle.fill")
                            }
                        }
                    }

                    if !result.corrections.isEmpty {
                        InfoCard(title: L("الأخطاء التي سيتذكرها المدرب"), systemImage: "bookmark.fill", tint: AppTheme.brandSecondary) {
                            ForEach(result.corrections) { correction in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(correction.original)
                                        .strikethrough()
                                        .environment(\.layoutDirection, .leftToRight)
                                    Text(correction.replacement)
                                        .font(.headline)
                                        .environment(\.layoutDirection, .leftToRight)
                                    Text(correction.reasonAr)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .accessibilityElement(children: .combine)
                                if correction.id != result.corrections.last?.id { Divider() }
                            }
                        }
                    }

                    if let task = result.nextTaskEn, !task.isEmpty {
                        InfoCard(title: L("استخدم ما تعلمته الآن"), systemImage: "arrow.triangle.2.circlepath") {
                            Text(task)
                                .environment(\.layoutDirection, .leftToRight)
                            Button(L("استخدم المهمة كنص جديد")) {
                                text = ""
                                self.result = nil
                                ToastCenter.shared.show(L("اكتب إجابتك للمهمة الجديدة"), style: .info)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
            .padding(AppTheme.screenPadding)
        }
        .screenBackground()
        .navigationTitle(L("مدرب الكتابة"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func run() {
        let value = trimmed
        guard !value.isEmpty, !loading else { return }
        loading = true
        errorMessage = nil
        Task {
            do {
                _ = await container.progressSyncService.pushIfStale()
                let analyzed = try await service.correctWriting(text: value, level: session.selectedLevel.rawValue)
                result = analyzed
                await recordLearning(from: analyzed, originalText: value)
                ToastCenter.shared.show(L("تم تحليل كتابتك وإضافة النتيجة إلى ملف تعلمك"))
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? L("تعذر تحليل الكتابة.")
            }
            loading = false
        }
    }

    private func recordLearning(from result: WritingResult, originalText: String) async {
        for correction in result.corrections.prefix(8) {
            await container.learningMemoryRepository.recordMistake(.init(
                id: UUID().uuidString,
                category: L("الكتابة"),
                source: L("مدرب الكتابة الذكي"),
                prompt: correction.original,
                learnerAnswer: correction.original,
                correction: correction.replacement,
                explanationAr: correction.reasonAr,
                createdAt: .now,
                reviewCount: 0,
                resolved: false
            ))
        }

        if let score = result.score {
            let wordCount = originalText.split { $0.isWhitespace || $0.isNewline }.count
            let record = PracticeSessionRecord(
                id: UUID().uuidString,
                domain: .writing,
                sourceID: "ai-writing",
                titleAr: L("تحليل كتابة بالذكاء الاصطناعي"),
                level: session.selectedLevel,
                score: Double(score) / 100,
                minutes: min(15, max(2, wordCount / 20 + 1)),
                createdAt: .now,
                details: Array((result.strengthsAr + result.improvementsAr).prefix(6))
            )
            await container.progressRepository.recordPracticeSession(record)
        }

        if container.accountService.isAuthenticated {
            _ = await container.progressSyncService.push(showFeedback: false)
        }
    }
}
