import Foundation
import PDFKit

/// Advisory comparison of extractable source text and the generated text.
/// Does not guess names, OCR scanned pages again or rewrite a result.
enum DocumentConsistencyAudit {
    static func numbers(_ text: String) -> Set<String> {
        let normalized = PageSelectionNormalizer.normalize(text)
        guard let pattern = try? NSRegularExpression(pattern: #"\p{Nd}+(?:[.,٫٬/:\-]\p{Nd}+)*"#) else { return [] }
        let range = NSRange(normalized.startIndex..., in: normalized)
        return Set(pattern.matches(in: normalized, range: range).compactMap { match in
            Range(match.range, in: normalized).map { String(normalized[$0]) }
        })
    }
    static func review(source: URL, output: URL, options: ConversionOptions, report: QualityReport?) -> QualityReport? {
        guard var report else { return nil }
        // Range-limited source comparison needs its own page evidence; do not
        // compare a selected result against an entire source document.
        guard options.pageSelection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return report }
        let original: String
        if source.pathExtension.lowercased() == "pdf", let pdf = PDFDocument(url: source) {
            original = String((pdf.string ?? "").prefix(600_000))
        } else if source.pathExtension.lowercased() == "docx", let document = try? DocxExtractor.parse(url: source) {
            original = String(document.blocks.compactMap(\.markdown).joined(separator: "\n").prefix(600_000))
        } else { return report }
        guard original.count > 50, let result = try? DocxExtractor.parse(url: output) else { return report }
        let generated = result.blocks.compactMap(\.markdown).joined(separator: "\n")
        report.numbersRequiringReview = numbers(original).subtracting(numbers(generated)).count
        if options.operation == .translate {
            report.glossaryTermsRequiringReview = (options.translation?.usableGlossary ?? []).filter { term in
                original.localizedCaseInsensitiveContains(term.source) && !generated.localizedCaseInsensitiveContains(term.target)
            }.count
        }
        return report
    }
}
