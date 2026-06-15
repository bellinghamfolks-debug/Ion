import SwiftUI
import UIKit

struct CopyButton: View {
    let text: String
    @State private var copied = false

    var body: some View {
        Button {
            UIPasteboard.general.string = text
            copied = true
            UIAccessibility.post(
                notification: .announcement,
                argument: L10n.t("نُسخ النص إلى الحافظة.", "Text copied to the clipboard.")
            )
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                copied = false
            }
        } label: {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
        }
        .buttonStyle(BasirIconButtonStyle())
        .accessibilityLabel(
            copied ? L10n.t("تم النسخ", "Copied")
                   : L10n.t("نسخ النص", "Copy text")
        )
        .accessibilityHint(L10n.t(
            "ينسخ النص الكامل إلى الحافظة.",
            "Copies the full text to the clipboard."
        ))
    }
}
