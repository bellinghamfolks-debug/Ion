// HomeView.swift  (Talk tab)
// Mirrors Android renderTalkTab(): section "Questions and conversation"
// with Ask Basir + Continuous voice conversation.

import SwiftUI

struct HomeView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Hero()

                    SectionHeader(L10n.t("تحدث مع بصير",
                                          "Talk with Basir"))

                    NavigationLink {
                        AskBasirView()
                    } label: {
                        BasirCard(
                            icon: "💬",
                            title: L10n.t("اسأل بصير", "Ask Basir"),
                            description: L10n.t(
                                "اكتب سؤالك أو انطقه بصوتك، ثم راجع المعلومات المهمة قبل استخدام الإجابة.",
                                "Type your question or say it aloud, then verify important information before using the answer."
                            )
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        VoiceConversationView()
                    } label: {
                        BasirCard(
                            icon: "🎙️",
                            title: L10n.t("محادثة صوتية",
                                          "Voice conversation"),
                            description: L10n.t(
                                "تحدث دون كتابة. يستمع بصير لسؤالك، يجيب بصوت، ثم يستعد تلقائيًا للسؤال التالي.",
                                "Talk without typing. Basir listens, answers aloud, then gets ready for your next question."
                            )
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(20)
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Reusable building blocks

struct Hero: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.t("بصير", "Basir"))
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(.white)
                .accessibilityAddTraits(.isHeader)
            Text(L10n.t(
                "افهم الصور والمستندات، ترجم النصوص، وتحدث بصوتك",
                "Understand images and documents, translate text, and ask by voice"
            ))
            .font(.body)
            .foregroundStyle(.white.opacity(0.85))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
        .background(
            LinearGradient(
                colors: [Color(red: 6/255, green: 35/255, blue: 86/255),
                         Color(red: 11/255, green: 58/255, blue: 130/255)],
                startPoint: .top, endPoint: .bottom
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

struct SectionHeader: View {
    let title: String
    init(_ title: String) { self.title = title }
    var body: some View {
        Text(title)
            .font(.subheadline.bold())
            .foregroundStyle(.secondary)
            .padding(.top, 8)
            .accessibilityAddTraits(.isHeader)
    }
}

struct BasirCard: View {
    /// An emoji glyph, matching the Android cards (addRichCard icon).
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 48, height: 48)
                Text(icon)
                    .font(.title2)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title3.bold())
                Text(description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.forward")
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.primary.opacity(0.07))
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title). \(description)")
        .accessibilityAddTraits(.isButton)
    }
}
