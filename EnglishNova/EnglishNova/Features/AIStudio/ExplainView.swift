import SwiftUI

struct ExplainView: View {
    @EnvironmentObject private var session: UserSession
    @State private var concept = ""
    @State private var result: ExplainResult?
    @State private var loading = false
    @State private var errorMessage: String?

    var initialConcept: String? = nil

    private let service = AIStudioService()
    private let suggestions = ["Present Perfect", "a vs an", "much vs many", "used to", "Phrasal verbs"]

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                InfoCard(title: L("شرح كلمة أو قاعدة"), systemImage: "text.book.closed.fill") {
                    Text(L("اكتب كلمة أو قاعدة بالإنجليزية. سيشرحها المدرّب بالعربية بما يناسب مستواك، مع مثال بالإنجليزية."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    HStack {
                        Image(systemName: "text.book.closed")
                            .foregroundStyle(.secondary)
                            .frame(width: 22)
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
                                Button(item) {
                                    concept = item
                                    run()
                                }
                                .font(.caption)
                                .buttonStyle(.bordered)
                                .environment(\.layoutDirection, .leftToRight)
                            }
                        }
                    }

                    PrimaryButton(
                        title: L("عرض الشرح"),
                        systemImage: "sparkles",
                        isLoading: loading,
                        isDisabled: trimmed.isEmpty
                    ) { run() }
                }

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let result {
                    InfoCard(title: L("الشرح"), systemImage: "lightbulb.fill", tint: AppTheme.accentTeal) {
                        Text(result.explanationAr)
                        if let example = result.exampleEn, !example.isEmpty {
                            Divider()
                            Text(L("مثال"))
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
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
        .navigationTitle(L("شرح كلمة أو قاعدة"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if let initialConcept, concept.isEmpty, result == nil {
                concept = initialConcept
                run()
            }
        }
    }

    private var trimmed: String {
        concept.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func run() {
        let query = trimmed
        guard !query.isEmpty, !loading else { return }
        loading = true
        errorMessage = nil

        Task {
            do {
                result = try await service.explain(
                    concept: query,
                    level: session.selectedLevel.rawValue
                )
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? L("تعذر إعداد الشرح.")
            }
            loading = false
        }
    }
}
