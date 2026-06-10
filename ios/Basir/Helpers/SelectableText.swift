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
    private let previewLimit = 12_000

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
///
/// CRITICAL: with `isScrollEnabled = false` a UITextView has no bounded
/// width during SwiftUI's layout pass, so for a large result it tries to
/// lay the text out as ONE enormous line and the layout hangs. We pin the
/// width to SwiftUI's proposed width via `sizeThatFits`, which forces the
/// text to wrap and report a correct finite height — no hang.
private struct SelectableTextViewRepresentable: UIViewRepresentable {
    let text: String

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.isEditable = false
        tv.isSelectable = true
        tv.isScrollEnabled = false          // let SwiftUI's ScrollView scroll
        tv.backgroundColor = .clear
        tv.textColor = .label
        tv.tintColor = UIColor(BasirTheme.brand)
        tv.textContainerInset = .zero
        tv.textContainer.lineFragmentPadding = 0
        tv.textContainer.lineBreakMode = .byWordWrapping
        tv.adjustsFontForContentSizeCategory = true
        tv.font = UIFont.preferredFont(forTextStyle: .body)
        tv.dataDetectorTypes = [.link, .phoneNumber]
        // Keep paragraph direction natural so Arabic, English, phone numbers,
        // and links can coexist without the whole result being forced into one
        // direction. The surrounding SwiftUI screen still follows the selected
        // app language.
        tv.semanticContentAttribute = .unspecified
        tv.textAlignment = .natural
        // Allow the view to be compressed/expanded horizontally to the
        // width SwiftUI gives it; resist vertical compression so the full
        // (wrapped) height is shown.
        tv.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        tv.setContentCompressionResistancePriority(.required, for: .vertical)
        tv.setContentHuggingPriority(.required, for: .vertical)
        return tv
    }

    func updateUIView(_ tv: UITextView, context: Context) {
        if tv.text != text { tv.text = text }
        // Keep paragraph direction natural so Arabic, English, phone numbers,
        // and links can coexist without the whole result being forced into one
        // direction. The surrounding SwiftUI screen still follows the selected
        // app language.
        tv.semanticContentAttribute = .unspecified
        tv.textAlignment = .natural
    }

    /// Bound the width to SwiftUI's proposal so the text wraps and the
    /// height is computed against that finite width (prevents the
    /// single-giant-line layout hang on large results).
    func sizeThatFits(_ proposal: ProposedViewSize,
                      uiView: UITextView,
                      context: Context) -> CGSize? {
        let width = proposal.width ?? UIScreen.main.bounds.width
        guard width > 0, width.isFinite else { return nil }
        let fitting = uiView.sizeThatFits(
            CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: ceil(fitting.height))
    }
}
