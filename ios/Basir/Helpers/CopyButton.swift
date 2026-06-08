// CopyButton.swift
// Small reusable "copy to clipboard" control for result screens, so the
// user can always copy output even when the iOS share sheet is awkward
// on a sideloaded build.

import SwiftUI
import UIKit

struct CopyButton: View {
    let text: String
    @State private var copied = false

    var body: some View {
        Button {
            UIPasteboard.general.string = text
            copied = true
            UIAccessibility.post(notification: .announcement,
                                 argument: L10n.t("تم النسخ", "Copied"))
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
        } label: {
            Label(copied ? L10n.t("تم النسخ", "Copied") : L10n.t("نسخ", "Copy"),
                  systemImage: copied ? "checkmark" : "doc.on.doc")
        }
        .accessibilityLabel(L10n.t("نسخ النتيجة", "Copy result"))
    }
}
