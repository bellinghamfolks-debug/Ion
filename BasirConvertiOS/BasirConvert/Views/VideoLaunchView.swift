import SwiftUI

/// Shown once, to say what is new: Basir now watches videos.
struct VideoLaunchView: View {
    @EnvironmentObject private var l10n: L10n
    @Environment(\.dismiss) private var dismiss
    @State private var tryNow = false
    @AccessibilityFocusState private var titleFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: BasirSpacing.l) {
                    Image(systemName: "play.rectangle.on.rectangle.fill")
                        .font(.system(size: 64, weight: .semibold))
                        .foregroundStyle(BasirPalette.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.top, BasirSpacing.l)
                        .accessibilityHidden(true)
                    Text(l10n.t("جديد في بصير: وصف الفيديو", "New in Basir: Video description"))
                        .font(.largeTitle.weight(.bold))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityFocused($titleFocused)
                    Text(l10n.t("الآن يشاهد بصير الفيديو معك ويصفه لك.", "Now Basir watches videos with you and describes them."))
                        .font(.title3)
                        .fixedSize(horizontal: false, vertical: true)
                    feature("film.stack", l10n.t("فيديو من ألبومك أو رابط YouTube، مدته حتى ساعة.",
                                                 "A video from your album or a YouTube link, up to an hour long."))
                    feature("list.bullet.rectangle", l10n.t("فصول بأوقاتها، وما يظهر في كل مشهد، والنصوص على الشاشة، ومن يتكلم.",
                                                            "Chapters with their times, what appears in each scene, the text on screen, and who speaks."))
                    feature("questionmark.bubble", l10n.t("اسأل الفيديو ما تريد، مثل: ماذا كان مكتوبًا على اللوحة؟",
                                                          "Ask the video anything, like: what was written on the sign?"))
                    feature("square.and.arrow.up", l10n.t("من تطبيق YouTube مباشرة: اضغط «مشاركة» ثم اختر «بصير».",
                                                          "Straight from the YouTube app: tap Share, then choose Basir."))
                    PrimaryActionButton(title: l10n.t("جرّبها الآن", "Try it now"), systemImage: "play.fill") { tryNow = true }
                    CardActionButton(title: l10n.t("لاحقًا", "Later"), systemImage: "clock") { dismiss() }
                }
                .appScreenContent()
            }
            .background(BasirPalette.background.ignoresSafeArea())
            .foregroundStyle(BasirPalette.primaryText)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(l10n.t("إغلاق", "Close")) { dismiss() } }
            }
        }
        .escapeToDismiss { dismiss() }
        .onAppear { titleFocused = true }
        .fullScreenCover(isPresented: $tryNow, onDismiss: { dismiss() }) {
            VideoDescribeView()
        }
    }

    private func feature(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: BasirSpacing.m) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(BasirPalette.accent)
                .frame(width: 32)
                .accessibilityHidden(true)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
        .padding(BasirSpacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BasirPalette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
