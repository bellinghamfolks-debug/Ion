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
                 text: l10n.t("حوّل ملفات PDF والصور والعروض والتسجيلات إلى ملفات Word مرتبة وسهلة القراءة، أو ترجمها إلى لغتك.",
                              "Turn PDFs, images, presentations, and recordings into well-structured Word files that are easy to read, or translate them.")),
            Page(icon: "plus.circle.fill",
                 title: l10n.t("ابدأ من «جديد»", "Start from New"),
                 text: l10n.t("اختر ملفًا أو امسح مستندًا أو التقط صورة أو الصق صورة. تظهر المهمة في شريط صغير أسفل الشاشة، ويمكنك متابعة استخدام التطبيق.",
                              "Choose a file, scan a document, take a photo, or paste an image. The task appears in a small bar at the bottom, so you can keep using the app.")),
            Page(icon: "checkmark.shield.fill",
                 title: l10n.t("نتائج موثوقة", "Results you can trust"),
                 text: l10n.t("يتحقق بصير من كل ملف Word قبل حفظه، ويخبرك بما قُرئ وما يحتاج مراجعة. مستخدمو VoiceOver: النقر مرتين بإصبعين يوقف المهمة أو يستأنفها.",
                              "Basir checks every Word file before saving it and tells you what was read and what needs review. VoiceOver users: a two-finger double-tap pauses or resumes a task."))
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
