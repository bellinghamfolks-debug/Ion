import Foundation
import UIKit

/// The summary as lines in reading order: one source for listening (ت14),
/// the audio file, the PDF and the shared text (ت16), so they never differ.
@MainActor
enum SummaryExport {
    struct Line: Equatable {
        enum Kind: Equatable { case title, heading, text, item }
        let kind: Kind
        let text: String
    }

    static func lines(_ summary: DocumentSummary, title: String, l10n: L10n) -> [Line] {
        var lines: [Line] = [Line(kind: .title, text: l10n.t("ملخص: \(title)", "Summary: \(title)"))]
        if !summary.documentType.isEmpty { lines.append(Line(kind: .text, text: summary.documentType)) }
        if !summary.notice.isEmpty { lines.append(Line(kind: .text, text: summary.notice)) }
        func overview(_ heading: String, _ value: DocumentSummary.Overview) {
            guard !value.text.isEmpty else { return }
            lines.append(Line(kind: .heading, text: heading))
            lines.append(Line(kind: .text, text: value.text + flags(value.flaggedNumbers, l10n: l10n)))
        }
        overview(l10n.t("باختصار", "In one line"), summary.oneLine)
        overview(l10n.t("الملخص", "Summary"), summary.short)
        if !summary.keyPoints.isEmpty {
            lines.append(Line(kind: .heading, text: l10n.t("أهم النقاط", "Key points")))
            lines += summary.keyPoints.map { Line(kind: .item, text: describe($0, in: summary, l10n: l10n)) }
        }
        for group in summary.groups where !group.points.isEmpty {
            lines.append(Line(kind: .heading, text: group.heading))
            lines += group.points.map { Line(kind: .item, text: describe($0, in: summary, l10n: l10n)) }
        }
        if !summary.sections.isEmpty {
            lines.append(Line(kind: .heading, text: l10n.t("ملخص الأقسام", "Section by section")))
            for section in summary.sections {
                lines.append(Line(kind: .item, text: section.title + pages(of: section, in: summary, l10n: l10n)
                                  + ": " + section.summary))
            }
        }
        overview(l10n.t("بلغة مبسطة", "In simple words"), summary.easyRead)
        if !summary.cards.isEmpty {
            lines.append(Line(kind: .heading, text: l10n.t("بطاقات المراجعة", "Study cards")))
            lines += summary.cards.map { Line(kind: .item, text: "\($0.front) — \($0.back)") }
        }
        if !summary.quiz.isEmpty {
            lines.append(Line(kind: .heading, text: l10n.t("أسئلة للمراجعة", "Review questions")))
            for (number, question) in summary.quiz.enumerated() {
                let answer = question.choices.indices.contains(question.answerIndex) ? question.choices[question.answerIndex] : ""
                lines.append(Line(kind: .item, text: "\(number + 1). \(question.question) — "
                                  + l10n.t("الإجابة: \(answer)", "Answer: \(answer)")))
            }
        }
        let check = summary.verification
        if check.pointsTotal > 0 {
            lines.append(Line(kind: .text, text: verificationSentence(check, l10n: l10n)))
        }
        return lines
    }

    static func verificationSentence(_ check: DocumentSummary.Verification, l10n: L10n) -> String {
        l10n.t("تحقق بصير من \(check.pointsVerified) من \(check.pointsTotal) نقطة في نص المستند نفسه.",
               "Basir confirmed \(check.pointsVerified) of \(check.pointsTotal) points in the document text itself.")
    }

    static func describe(_ point: DocumentSummary.Point, in summary: DocumentSummary, l10n: L10n) -> String {
        var text = point.text
        if !point.owner.isEmpty { text += l10n.t(" — المسؤول: \(point.owner)", " — Owner: \(point.owner)") }
        if !point.deadline.isEmpty { text += l10n.t(" — الموعد: \(point.deadline)", " — Deadline: \(point.deadline)") }
        text += whereLabel(point.locations, in: summary, l10n: l10n).map { " (\($0))" } ?? ""
        if !point.verified { text += l10n.t(" [غير مؤكد في النص]", " [not confirmed in the text]") }
        return text + flags(point.flaggedNumbers, l10n: l10n)
    }

    static func whereLabel(_ locations: [DocumentSummary.Location], in summary: DocumentSummary,
                           l10n: L10n) -> String? {
        guard !locations.isEmpty else { return nil }
        let several = summary.files.count > 1
        let parts = locations.map { location -> String in
            let file = several ? l10n.t("الملف \(location.file + 1)، ", "file \(location.file + 1), ") : ""
            return summary.usesPages(file: location.file)
                ? file + l10n.t("ص \(location.page)", "p. \(location.page)")
                : file + l10n.t("الجزء \(location.page)", "part \(location.page)")
        }
        return parts.joined(separator: l10n.t("، ", ", "))
    }

    static func pages(of section: DocumentSummary.Section, in summary: DocumentSummary, l10n: L10n) -> String {
        guard section.firstPage > 0 else { return "" }
        let pages = summary.usesPages(file: section.file)
        if section.lastPage <= section.firstPage {
            return pages ? l10n.t(" (ص \(section.firstPage))", " (p. \(section.firstPage))")
                         : l10n.t(" (الجزء \(section.firstPage))", " (part \(section.firstPage))")
        }
        return pages ? l10n.t(" (ص \(section.firstPage)–\(section.lastPage))", " (pp. \(section.firstPage)–\(section.lastPage))")
                     : l10n.t(" (الأجزاء \(section.firstPage)–\(section.lastPage))", " (parts \(section.firstPage)–\(section.lastPage))")
    }

    static func flags(_ numbers: [String], l10n: L10n) -> String {
        guard !numbers.isEmpty else { return "" }
        return l10n.t(" [رقم لم يُعثر عليه في النص: \(numbers.joined(separator: "، "))]",
                      " [number not found in the text: \(numbers.joined(separator: ", "))]")
    }

    static func plainText(_ summary: DocumentSummary, title: String, l10n: L10n) -> String {
        lines(summary, title: title, l10n: l10n).map { line in
            switch line.kind {
            case .title: return line.text + "\n"
            case .heading: return "\n" + line.text
            case .item: return "• " + line.text
            case .text: return line.text
            }
        }.joined(separator: "\n")
    }

    /// Passages for listening and the audio file: headings announced as such.
    static func spokenPassages(_ summary: DocumentSummary, title: String, l10n: L10n) -> [String] {
        lines(summary, title: title, l10n: l10n).map { line in
            line.kind == .heading ? l10n.t("عنوان: \(line.text)", "Heading: \(line.text)") : line.text
        }
    }

    /// A tagged-reading-order PDF made on the phone.
    static func pdf(_ summary: DocumentSummary, title: String, l10n: L10n) throws -> URL {
        let rtl = summary.language == "ar"
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = rtl ? .right : .left
        paragraph.baseWritingDirection = rtl ? .rightToLeft : .leftToRight
        paragraph.paragraphSpacing = 6
        let document = NSMutableAttributedString()
        for line in lines(summary, title: title, l10n: l10n) {
            let font: UIFont
            switch line.kind {
            case .title: font = .systemFont(ofSize: 20, weight: .bold)
            case .heading: font = .systemFont(ofSize: 16, weight: .semibold)
            case .item, .text: font = .systemFont(ofSize: 12.5)
            }
            let text = (line.kind == .item ? "• " : "") + line.text + "\n"
            document.append(NSAttributedString(string: text, attributes: [.font: font, .paragraphStyle: paragraph]))
        }
        let page = CGRect(x: 0, y: 0, width: 595, height: 842)
        let margin: CGFloat = 48
        let renderer = UIGraphicsPDFRenderer(bounds: page)
        let data = renderer.pdfData { context in
            let storage = NSTextStorage(attributedString: document)
            let layout = NSLayoutManager()
            storage.addLayoutManager(layout)
            var glyph = 0
            while glyph < layout.numberOfGlyphs || glyph == 0 {
                let container = NSTextContainer(size: CGSize(width: page.width - margin * 2, height: page.height - margin * 2))
                layout.addTextContainer(container)
                let range = layout.glyphRange(for: container)
                guard range.length > 0 else { break }
                context.beginPage()
                layout.drawGlyphs(forGlyphRange: range, at: CGPoint(x: margin, y: margin))
                glyph = NSMaxRange(range)
            }
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(fileName(title, l10n: l10n)).appendingPathExtension("pdf")
        try data.write(to: url, options: .atomic)
        return url
    }

    static func textFile(_ summary: DocumentSummary, title: String, l10n: L10n) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(fileName(title, l10n: l10n)).appendingPathExtension("txt")
        try plainText(summary, title: title, l10n: l10n).write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    static func fileName(_ title: String, l10n: L10n) -> String {
        let cleaned = title.replacingOccurrences(of: "/", with: "-").trimmingCharacters(in: .whitespacesAndNewlines)
        return l10n.t("ملخص \(cleaned.isEmpty ? "المستند" : cleaned)", "Summary of \(cleaned.isEmpty ? "document" : cleaned)")
    }
}
