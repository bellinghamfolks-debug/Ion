import SwiftUI

/// "اشرح لي" — ask the server AI to explain any English grammar point or word
/// in Arabic, with a simple example. Powered by /ai/explain (cached server-side).
struct ExplainView: View {
    @EnvironmentObject private var session: UserSession
    @State private var concept = ""
    @State private var result: ExplainResult?
    @State private var loading = false
    @State private var errorMessage: String?

    /// When set (e.g. from a lesson), the view pre-fills this concept and
    /// explains it automatically on appear.
    var initialConcept: String? = nil

    private let service = AIStudioService()
    private let suggestions = ["Present Perfect", "a vs an", "much vs many", "used to", "Phrasal verbs"]

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                InfoCard(title: L("اشرح لي"), systemImage: "sparkles") {
                    Text(L("اكتب أي قاعدة أو كلمة إنجليزية وسيشرحها لك المدرّب بالعربية مع مثال بسيط."))
                        .font(.footnote).foregroundStyle(.secondary)

                    HStack {
                        Image(systemName: "text.book.closed").foregroundStyle(.secondary).frame(width: 22)
                        TextField(L("مثال: Present Perfect"), text: $concept)
                            .environment(\.layoutDirection, .leftToRight)
                            .submitLabel(.go)
                            .onSubmit(run)
                    }
                    .padding(12)
                    .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(suggestions, id: \.self) { item in
                                Button(item) { concept = item; run() }
                                    .font(.caption)
                                    .buttonStyle(.bordered)
                                    .environment(\.layoutDirection, .leftToRight)
                            }
                        }
                    }

                    PrimaryButton(title: L("اشرح"), systemImage: "wand.and.stars", isLoading: loading,
                                  isDisabled: trimmed.isEmpty) { run() }
                }

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote).foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let result {
                    InfoCard(title: L("الشرح"), systemImage: "lightbulb.fill", tint: AppTheme.accentTeal) {
                        Text(result.explanationAr)
                        if let example = result.exampleEn, !example.isEmpty {
                            Divider()
                            Label(L("مثال"), systemImage: "quote.opening")
                                .font(.caption.bold()).foregroundStyle(.secondary)
                            Text(example)
                                .font(.body.weight(.medium))
                                .environment(\.layoutDirection, .leftToRight)
                        }
                    }
                }
            }
            .padding(AppTheme.screenPadding)
        }
        .screenBackground()
        .navigationTitle(L("اشرح لي"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if let initialConcept, concept.isEmpty, result == nil {
                concept = initialConcept
                run()
            }
        }
    }

    private var trimmed: String { concept.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func run() {
        let query = trimmed
        guard !query.isEmpty, !loading else { return }
        loading = true
        errorMessage = nil
        Task {
            do {
                result = try await service.explain(concept: query, level: session.selectedLevel.rawValue)
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? L("تعذّر الشرح.")
            }
            loading = false
        }
    }
}
