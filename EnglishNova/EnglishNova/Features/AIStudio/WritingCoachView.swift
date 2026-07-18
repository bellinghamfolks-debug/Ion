import SwiftUI

/// Writing coach — the learner writes English, the server AI corrects it,
/// scores it, and explains the fixes in Arabic. Powered by /ai/writing.
struct WritingCoachView: View {
    @EnvironmentObject private var session: UserSession
    @State private var text = ""
    @State private var result: WritingResult?
    @State private var loading = false
    @State private var errorMessage: String?

    private let service = AIStudioService()

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                InfoCard(title: L("مصحّح الكتابة"), systemImage: "pencil.and.scribble") {
                    Text(L("اكتب جملة أو فقرة بالإنجليزية، وسيصححها المدرّب، ويمنحها درجة، ويشرح الأخطاء بالعربية."))
                        .font(.footnote).foregroundStyle(.secondary)

                    TextEditor(text: $text)
                        .frame(minHeight: 130)
                        .environment(\.layoutDirection, .leftToRight)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))

                    PrimaryButton(title: L("صحّح كتابتي"), systemImage: "checkmark.seal.fill", isLoading: loading,
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
                    InfoCard(title: L("النص المصحّح"), systemImage: "text.badge.checkmark", tint: AppTheme.success) {
                        Text(result.corrected)
                            .font(.body.weight(.medium))
                            .environment(\.layoutDirection, .leftToRight)
                            .textSelection(.enabled)
                    }
                    InfoCard(title: L("الملاحظات"), systemImage: "text.bubble.fill", tint: AppTheme.warning) {
                        Text(result.feedbackAr)
                    }
                }
            }
            .padding(AppTheme.screenPadding)
        }
        .screenBackground()
        .navigationTitle(L("مصحّح الكتابة"))
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
                result = try await service.correctWriting(text: value, level: session.selectedLevel.rawValue)
                ToastCenter.shared.show(L("تم تصحيح كتابتك"))
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? L("تعذّر التصحيح.")
            }
            loading = false
        }
    }
}
