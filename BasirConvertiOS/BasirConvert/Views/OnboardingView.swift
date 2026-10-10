import SwiftUI

/// Three short, skippable screens shown on first launch.
struct OnboardingView: View {
    @EnvironmentObject private var l10n: L10n
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AccessibilityFocusState private var headingFocused: Bool
    @State private var page = 0
    let onFinish: () -> Void

    private struct Page {
        let icon: String
        let title: String
        let text: String
    }

    private var pages: [Page] {
        [
            Page(icon: "doc.richtext.fill",
                 title: l10n.t("أهلًا بك في بصير", "Welcome to Basir"),
                 text: l10n.t("حوّل مستنداتك وصورك وتسجيلاتك إلى ملفات Word سهلة القراءة، وترجم مستنداتك إلى اللغة التي تختارها.",
                              "Turn documents, images, and recordings into Word files that are easy to read. Translate documents into your chosen language.")),
            Page(icon: "plus.circle.fill",
                 title: l10n.t("اختر ملفك وابدأ", "Choose a file to begin"),
                 text: l10n.t("من تبويب «جديد»، أضف ملفًا أو صوّر مستندًا. تابع تقدم المهمة من الشريط أسفل الشاشة، وواصل استخدام بصير أثناء المعالجة.",
                              "Add a file or scan a document from the New tab. Follow its progress in the bar at the bottom while you keep using Basir.")),
            Page(icon: "checkmark.shield.fill",
                 title: l10n.t("اقرأ نتيجتك وراجعها", "Read and review your result"),
                 text: l10n.t("تجد نتائجك في «ملفاتي»، مع تقرير يوضح جودة الملف وما يحتاج إلى مراجعة. مع VoiceOver، انقر مرتين بإصبعين لإيقاف المهمة مؤقتًا أو استئنافها.",
                              "Find your results in My files, with a quality report and any points to review. With VoiceOver, double-tap with two fingers to pause or resume a task."))
        ]
    }

    var body: some View {
        let current = pages[page]
        ZStack {
            AuroraBackground()
            VStack(alignment: .leading, spacing: BasirSpacing.xl) {
                HStack {
                    Text(l10n.t("\(page + 1) من \(pages.count)", "\(page + 1) of \(pages.count)"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(BasirPalette.secondaryText)
                    Spacer()
                    Button(l10n.t("تخطي", "Skip")) { finish() }
                        .font(.body.weight(.semibold))
                        .foregroundStyle(BasirPalette.accent)
                        .frame(minHeight: 44)
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: BasirSpacing.l) {
                        Image(systemName: current.icon)
                            .font(.system(size: 44, weight: .semibold))
                            .foregroundStyle(BasirPalette.onAccent)
                            .frame(width: 88, height: 88)
                            .background(BasirPalette.accent, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                            .accessibilityHidden(true)
                        Text(current.title)
                            .font(.system(.largeTitle, design: .rounded, weight: .bold))
                            .foregroundStyle(BasirPalette.primaryText)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                            .accessibilityFocused($headingFocused)
                        Text(current.text)
                            .font(.title3)
                            .foregroundStyle(BasirPalette.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .id(page)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .trailing)))
                }
                HStack(spacing: BasirSpacing.s) {
                    ForEach(0..<pages.count, id: \.self) { index in
                        Capsule()
                            .fill(index == page ? BasirPalette.accent : BasirPalette.stroke)
                            .frame(width: index == page ? 24 : 8, height: 8)
                    }
                }
                .accessibilityHidden(true)
                AdaptiveStack {
                    if page > 0 {
                        SecondaryActionButton(title: l10n.t("السابق", "Back"), systemImage: "chevron.backward") {
                            go(to: page - 1)
                        }
                    }
                    PrimaryActionButton(
                        title: page == pages.count - 1 ? l10n.t("ابدأ", "Get started") : l10n.t("التالي", "Next"),
                        systemImage: page == pages.count - 1 ? "checkmark" : "chevron.forward"
                    ) {
                        if page == pages.count - 1 { finish() } else { go(to: page + 1) }
                    }
                }
            }
            .padding(.horizontal, BasirSpacing.xl)
            .padding(.vertical, BasirSpacing.l)
        }
        .escapeToDismiss { finish() }
        .onAppear { headingFocused = true }
    }

    private func go(to index: Int) {
        if reduceMotion {
            page = index
        } else {
            withAnimation(.easeInOut(duration: 0.25)) { page = index }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { headingFocused = true }
    }

    private func finish() {
        onFinish()
    }
}
