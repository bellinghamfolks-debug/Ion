// SelectableText.swift
// A safe, reusable result-text view.
//
// Why this exists
// ───────────────
// SwiftUI's `Text(huge).textSelection(.enabled)` hits a hard
// performance cliff with large strings: a converted document can be
// hundreds of pages, and rendering all of it through SwiftUI Text —
// while ALSO duplicating the whole string as an `.accessibilityLabel`
// — froze and then crashed the app right after a conversion finished.
//
// This wraps a non-editable, selectable UITextView, which lays out
// large text far more efficiently and exposes the text to VoiceOver
// natively (no redundant accessibilityLabel needed). To stay snappy on
// truly huge results we render a generous *preview* inline; the full
// text is always available through Copy / Share / Word right next to
// it, so nothing is lost.
//
// Drop-in replacement for:
//     Text(s).textSelection(.enabled).accessibilityLabel(s)

import SwiftUI
import UIKit

struct SelectableText: View {
    let text: String

    /// Characters shown inline before we truncate the *preview*. The
    /// full string is still copyable/shareable; this only bounds what
    /// we lay out on screen so a 500-page result can never lock the UI.
    private let previewLimit = 20_000

    private var isTruncated: Bool { text.count > previewLimit }

    private var preview: String {
        isTruncated ? String(text.prefix(previewLimit)) : text
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SelectableTextViewRepresentable(text: preview)
            if isTruncated {
                Label(
                    L10n.t(
                        "هذه معاينة لبداية النص. النص كامل متاح عبر النسخ أو المشاركة أو ملف Word.",
                        "This is a preview of the beginning. The full text is available via Copy, Share, or the Word file."
                    ),
                    systemImage: "info.circle"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }
}

/// UITextView-backed text: non-editable but selectable, sizes to its
/// content so it flows inside a SwiftUI ScrollView, follows Dynamic
/// Type, and respects the app's RTL/LTR layout direction.
private struct SelectableTextViewRepresentable: UIViewRepresentable {
    let text: String

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.isEditable = false
        tv.isSelectable = true
        tv.isScrollEnabled = false          // let SwiftUI's ScrollView scroll
        tv.backgroundColor = .clear
        tv.textContainerInset = .zero
        tv.textContainer.lineFragmentPadding = 0
        tv.adjustsFontForContentSizeCategory = true
        tv.font = UIFont.preferredFont(forTextStyle: .body)
        tv.dataDetectorTypes = []
        // Hug content vertically; expand to the available width.
        tv.setContentCompressionResistancePriority(.required, for: .vertical)
        tv.setContentHuggingPriority(.required, for: .vertical)
        return tv
    }

    func updateUIView(_ tv: UITextView, context: Context) {
        if tv.text != text { tv.text = text }
    }
}
