import SwiftUI

struct HomeView: View {
    var body: some View {
        NavigationStack {
            BasirScreen {
                BasirHero(
                    eyebrow: L10n.t("المحادثة", "CONVERSATION"),
                    title: L10n.t("كيف أساعدك اليوم؟", "How can I help today?"),
                    subtitle: L10n.t(
                        "اكتب سؤالك أو تحدث بصوتك، وستبقى الإجابة واضحة وقابلة للنسخ والحفظ.",
                        "Type a question or speak naturally. Every answer stays clear, reviewable, and easy to save."
                    ),
                    systemImage: "bubble.left.and.bubble.right.fill"
                )

                BasirSectionHeader(
                    title: L10n.t("اختر طريقة المحادثة", "Choose how to talk"),
                    subtitle: L10n.t(
                        "يمكنك التبديل بين الكتابة والصوت في أي وقت.",
                        "Switch between typing and voice whenever you need."
                    )
                )

                NavigationLink {
                    AskBasirView()
                } label: {
                    BasirFeatureCard(
                        systemImage: "text.bubble.fill",
                        title: L10n.t("اكتب سؤالك", "Type a question"),
                        description: L10n.t(
                            "اكتب أو أمْلِ السؤال، ثم راجع الإجابة وانسخها أو اسأل عنها بتفصيل أكبر.",
                            "Type or dictate your question, then review, copy, or explore the answer in more detail."
                        )
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    VoiceConversationView()
                } label: {
                    BasirFeatureCard(
                        systemImage: "waveform.and.mic",
                        title: L10n.t("ابدأ محادثة صوتية", "Start a voice conversation"),
                        description: L10n.t(
                            "تحدث دون لمس الشاشة بعد كل إجابة. بصير يستمع ويجيب ثم يستعد للسؤال التالي.",
                            "Keep talking without touching the screen after every answer. Basir listens, replies, and gets ready again."
                        ),
                        badge: L10n.t("دون كتابة", "Hands-free")
                    )
                }
                .buttonStyle(.plain)

                BasirPageIntro(text: BasirCopy.verifyImportantInformation, tone: .warning)
            }
            .navigationTitle(L10n.t("المحادثة", "Conversation"))
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
