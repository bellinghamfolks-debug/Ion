// SharedItemView.swift
// Presented when another app shares content into Basir via the Share
// Extension. Shows the shared item and runs the matching Gemini task.

import SwiftUI
import UIKit

struct SharedItemView: View {
    let incoming: ShareInbox.Incoming
    @Environment(\.dismiss) private var dismiss

    @State private var result: String = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var isImage: Bool {
        ["jpg", "jpeg", "png", "heic", "heif", "gif"].contains(incoming.fileExtension)
    }
    private var isText: Bool { incoming.fileExtension == "txt" }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    preview

                    Button {
                        Task { await run() }
                    } label: {
                        HStack {
                            if isLoading { ProgressView().tint(.white) }
                            Text(isLoading
                                 ? L10n.t("أجهّز النتيجة...", "Preparing your result...")
                                 : actionTitle)
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity, minHeight: 54)
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .disabled(isLoading || (!isImage && !isText))

                    if !result.isEmpty {
                        Divider().padding(.vertical, 4)
                        Text(L10n.t("النتيجة", "Result"))
                            .font(.headline)
                            .accessibilityAddTraits(.isHeader)
                        SelectableText(text: result)
                        CopyButton(text: result)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.red.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
                .padding(20)
            }
            .navigationTitle(L10n.t("فتح في بصير", "Open in Basir"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.t("إغلاق", "Close")) { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private var preview: some View {
        if isImage, let image = UIImage(data: incoming.data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 260)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .accessibilityLabel(L10n.t("الصورة المستلمة", "Received image"))
        } else if isText, let text = String(data: incoming.data, encoding: .utf8) {
            Text(text)
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
        } else {
            Label(
                L10n.t("وصل ملف بصيغة \(incoming.fileExtension.uppercased()). افتح قسم المستندات لمعالجته.",
                       "A \(incoming.fileExtension.uppercased()) file was received. Open Documents to process it."),
                systemImage: "doc.fill"
            )
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }

    private var actionTitle: String {
        if isImage { return L10n.t("وصف الصورة", "Describe image") }
        if isText { return L10n.t("اسأل بصير", "Ask Basir") }
        return L10n.t("طريقة معالجة الملف", "How to process this file")
    }

    private func run() async {
        isLoading = true
        errorMessage = nil
        result = ""
        defer { isLoading = false }

        let lang = BasirSettings.shared.language
        do {
            if isImage {
                result = try await AiProviderFactory.current().ask(
                    task: .describeImage, input: "",
                    instruction: nil, language: lang,
                    imageData: incoming.data, mimeType: "image/jpeg")
            } else if isText, let text = String(data: incoming.data, encoding: .utf8) {
                result = try await AiProviderFactory.current().ask(
                    task: .ask, input: text,
                    instruction: nil, language: lang,
                    imageData: nil, mimeType: nil)
            } else {
                errorMessage = L10n.t(
                    "يمكن معالجة هذا النوع من الملفات من قسم المستندات.",
                    "This file type can be processed from the Documents section.")
                return
            }
            UIAccessibility.post(notification: .announcement,
                                 argument: L10n.t("النتيجة جاهزة.", "Your result is ready."))
        } catch {
            errorMessage = UserFriendlyErrorMapper.map(error)
        }
    }
}
