import SwiftUI

struct ArchiveView: View {
    @StateObject private var store = ArchiveStore.shared
    @State private var filter = "all"

    private var filtered: [ArchivedResult] {
        filter == "all" ? store.results : store.results.filter { $0.kind == filter }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker(L10n.t("تصفية النتائج", "Filter results"), selection: $filter) {
                Text(L10n.t("الكل", "All")).tag("all")
                Text(L10n.t("ترجمة", "Translation")).tag("translate")
                Text(L10n.t("صور", "Images")).tag("describe_image")
                Text(L10n.t("رياضيات", "Math")).tag("math_extract")
                Text(L10n.t("أسئلة", "Questions")).tag("ask")
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, BasirTheme.horizontalPadding)
            .padding(.vertical, 14)
            .background(BasirTheme.screenBackground)

            if filtered.isEmpty {
                BasirEmptyState(
                    systemImage: "archivebox",
                    title: L10n.t("لا توجد نتائج في هذا القسم", "No results in this category"),
                    message: L10n.t(
                        "النتائج التي تختار حفظها ستظهر هنا، ويمكن تغيير الحفظ التلقائي من الإعدادات.",
                        "Results you choose to save appear here. Automatic saving can be changed in Settings."
                    )
                )
                .padding(BasirTheme.horizontalPadding)
                Spacer()
            } else {
                List {
                    ForEach(filtered) { result in
                        NavigationLink {
                            ArchivedResultDetail(result: result)
                        } label: {
                            HStack(alignment: .top, spacing: 13) {
                                Image(systemName: icon(for: result.kind))
                                    .foregroundStyle(BasirTheme.brand)
                                    .frame(width: 34, height: 34)
                                    .background(BasirTheme.brand.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(result.title)
                                        .font(.body.weight(.semibold))
                                        .lineLimit(2)
                                    if !result.summary.isEmpty {
                                        Text(result.summary)
                                            .font(.callout)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }
                                    Text(result.createdAt, format: .dateTime.year().month().day())
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .padding(.vertical, 5)
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .onDelete { indexSet in
                        for index in indexSet { store.deleteResult(filtered[index].id) }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(BasirTheme.screenBackground)
            }
        }
        .background(BasirTheme.screenBackground.ignoresSafeArea())
        .navigationTitle(L10n.t("النتائج المحفوظة", "Saved results"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func icon(for kind: String) -> String {
        switch kind {
        case "translate", "translate_doc": return "character.book.closed.fill"
        case "describe_image", "image_describe": return "photo.fill"
        case "math_extract": return "function"
        case "convert": return "doc.text.fill"
        default: return "bubble.left.fill"
        }
    }
}

private struct ArchivedResultDetail: View {
    let result: ArchivedResult

    var body: some View {
        BasirScreen {
            BasirInfoRow(
                label: L10n.t("تاريخ الحفظ", "Saved on"),
                value: result.createdAt.formatted(date: .long, time: .shortened),
                systemImage: "calendar"
            )

            BasirResultCard(title: result.title, text: result.text) {
                HStack(spacing: 4) {
                    CopyButton(text: result.text)
                    ShareLink(item: result.text) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .buttonStyle(BasirIconButtonStyle())
                    .accessibilityLabel(L10n.t("مشاركة النتيجة", "Share result"))
                }
            }

            AskAboutResultLink(text: result.text)
        }
        .navigationTitle(L10n.t("تفاصيل النتيجة", "Result details"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
