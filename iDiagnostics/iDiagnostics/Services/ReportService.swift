import UIKit

/// Renders a diagnostics report to a PDF file. Arabic text is drawn via
/// `NSAttributedString` with a right-aligned paragraph style so it lays out
/// correctly right-to-left.
@MainActor
struct ReportService {

    // A4 in points (72 dpi): 595.2 x 841.8.
    private let pageSize = CGSize(width: 595.2, height: 841.8)
    private let margin: CGFloat = 40

    /// Builds the PDF and returns a URL to a temporary `.pdf` file, or nil on
    /// failure.
    func makePDF(snapshot: DeviceSnapshot, results: [TestResult], healthScore: Int) -> URL? {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize))
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("iDiagnostics-Report-\(Int(Date().timeIntervalSince1970)).pdf")

        do {
            try renderer.writePDF(to: url) { context in
                context.beginPage()
                var cursor: CGFloat = margin

                cursor = drawTitle(at: cursor)
                cursor = drawSnapshot(snapshot, at: cursor)
                cursor = drawHealthScore(healthScore, at: cursor)

                for result in results {
                    cursor = drawResult(result, startingAt: cursor, context: context)
                }
            }
            return url
        } catch {
            return nil
        }
    }

    // MARK: - Sections

    private func drawTitle(at y: CGFloat) -> CGFloat {
        var cursor = y
        cursor = draw("تقرير تشخيص الجهاز",
                      at: cursor,
                      font: .boldSystemFont(ofSize: 26),
                      color: .label)
        cursor = draw("iDiagnostics",
                      at: cursor + 2,
                      font: .systemFont(ofSize: 12),
                      color: .secondaryLabel)
        return cursor + 10
    }

    private func drawSnapshot(_ snapshot: DeviceSnapshot, at y: CGFloat) -> CGFloat {
        var cursor = y
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short

        let rows: [(String, String)] = [
            ("الجهاز", snapshot.marketingName),
            ("المعرّف", snapshot.modelIdentifier),
            ("نظام التشغيل", "\(snapshot.systemName) \(snapshot.systemVersion)"),
            ("تاريخ التقرير", df.string(from: snapshot.generatedAt)),
        ]
        for (label, value) in rows {
            cursor = draw("\(label): \(value)",
                          at: cursor,
                          font: .systemFont(ofSize: 13),
                          color: .label)
        }
        return cursor + 10
    }

    private func drawHealthScore(_ score: Int, at y: CGFloat) -> CGFloat {
        var cursor = y
        cursor = draw("درجة صحة الجهاز",
                      at: cursor,
                      font: .boldSystemFont(ofSize: 15),
                      color: .label)
        cursor = draw("\(score) / 100",
                      at: cursor + 2,
                      font: .boldSystemFont(ofSize: 34),
                      color: scoreColor(score))
        return cursor + 14
    }

    private func drawResult(_ result: TestResult,
                            startingAt y: CGFloat,
                            context: UIGraphicsPDFRendererContext) -> CGFloat {
        var cursor = y
        // Estimate the block height; start a new page if it won't fit.
        let estimated: CGFloat = 70 + CGFloat(result.metrics.count) * 18
        if cursor + estimated > pageSize.height - margin {
            context.beginPage()
            cursor = margin
        }

        cursor = draw(result.category.titleAr,
                      at: cursor,
                      font: .boldSystemFont(ofSize: 16),
                      color: .label)
        cursor = draw("الحالة: \(result.outcome.titleAr)",
                      at: cursor,
                      font: .boldSystemFont(ofSize: 13),
                      color: outcomeColor(result.outcome))

        if !result.summaryAr.isEmpty {
            cursor = draw(result.summaryAr,
                          at: cursor,
                          font: .systemFont(ofSize: 12),
                          color: .secondaryLabel)
        }
        for metric in result.metrics {
            cursor = draw("• \(metric.label): \(metric.value)",
                          at: cursor,
                          font: .systemFont(ofSize: 12),
                          color: .label)
        }

        // A light separator line.
        let sepY = cursor + 6
        let path = UIBezierPath()
        path.move(to: CGPoint(x: margin, y: sepY))
        path.addLine(to: CGPoint(x: pageSize.width - margin, y: sepY))
        UIColor.separator.setStroke()
        path.lineWidth = 0.5
        path.stroke()

        return sepY + 12
    }

    // MARK: - Drawing helper

    /// Draws one right-aligned (RTL) line of text and returns the y position
    /// just below it.
    @discardableResult
    private func draw(_ text: String, at y: CGFloat, font: UIFont, color: UIColor) -> CGFloat {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .right
        paragraph.baseWritingDirection = .rightToLeft

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph,
        ]
        let attributed = NSAttributedString(string: text, attributes: attributes)
        let maxWidth = pageSize.width - margin * 2
        let bounds = attributed.boundingRect(
            with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        attributed.draw(with: CGRect(x: margin, y: y, width: maxWidth, height: ceil(bounds.height)),
                        options: [.usesLineFragmentOrigin, .usesFontLeading],
                        context: nil)
        return y + ceil(bounds.height) + 4
    }

    private func scoreColor(_ score: Int) -> UIColor {
        switch score {
        case 80...:   return .systemGreen
        case 50..<80: return .systemOrange
        default:      return .systemRed
        }
    }

    private func outcomeColor(_ outcome: TestOutcome) -> UIColor {
        switch outcome {
        case .pass:        return .systemGreen
        case .fail:        return .systemRed
        case .warning:     return .systemOrange
        case .unsupported: return .systemGray
        case .notRun:      return .secondaryLabel
        }
    }
}
