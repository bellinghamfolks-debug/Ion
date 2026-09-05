import Foundation
import UIKit

enum ReportServiceError: LocalizedError {
    case cannotCreateExportDirectory
    case cannotEncode

    var errorDescription: String? {
        switch self {
        case .cannotCreateExportDirectory: return "تعذر إنشاء مجلد مؤقت للتقرير."
        case .cannotEncode: return "تعذر ترميز بيانات التقرير."
        }
    }
}

final class ReportService {
    private let fileManager: FileManager
    private let dateFormatter: DateFormatter

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "ar_SA")
        dateFormatter.calendar = Calendar(identifier: .gregorian)
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short
    }

    func makeText(session: DiagnosticSession) throws -> URL {
        let url = try exportURL(session: session, extension: "txt")
        try textReport(session: session).write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func makeJSON(session: DiagnosticSession) throws -> URL {
        let url = try exportURL(session: session, extension: "json")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(session) else { throw ReportServiceError.cannotEncode }
        try data.write(to: url, options: [.atomic])
        return url
    }

    @MainActor
    func makePDF(session: DiagnosticSession) throws -> URL {
        let url = try exportURL(session: session, extension: "pdf")
        let page = CGRect(x: 0, y: 0, width: 595, height: 842)
        let renderer = UIGraphicsPDFRenderer(bounds: page)

        try renderer.writePDF(to: url) { context in
            context.beginPage()
            var y: CGFloat = 42
            y = draw("تقرير iDiagnostics", style: .title, at: y, page: page)
            y = draw("جلسة: \(session.id.uuidString)", style: .small, at: y, page: page)
            y = draw("الجهاز: \(session.device.marketingName) — \(session.device.modelIdentifier)", style: .body, at: y, page: page)
            y = draw("النظام: \(session.device.systemName) \(session.device.systemVersion)", style: .body, at: y, page: page)
            y = draw("وقت التقرير: \(dateFormatter.string(from: session.updatedAt))", style: .body, at: y, page: page)
            y = draw("المؤشر: \(session.healthScore.map(String.init) ?? "غير محسوب") من 100 — الفحوص المكتملة: \(session.completedCount) من \(TestCategory.allCases.count)", style: .heading, at: y + 8, page: page)
            y = draw("تنبيه: هذا تقرير إرشادي مبني على واجهات iOS العامة وتأكيد المستخدم، وليس تشخيصًا معتمدًا من Apple.", style: .small, at: y, page: page)

            for category in TestCategory.allCases {
                let result = session.result(for: category)
                let required = estimatedHeight(for: result)
                if y + required > page.height - 48 {
                    context.beginPage()
                    y = 42
                }
                y = draw("\(category.titleAr): \(result.outcome.titleAr)", style: .heading, at: y + 10, page: page)
                if !result.summaryAr.isEmpty {
                    y = draw(result.summaryAr, style: .body, at: y, page: page)
                }
                y = draw("مصدر النتيجة: \(result.evidence.titleAr)", style: .small, at: y, page: page)
                for metric in result.metrics {
                    y = draw("• \(metric.label): \(metric.value)", style: .body, at: y, page: page)
                }
                if let limitation = result.limitationAr {
                    y = draw("حدود الفحص: \(limitation)", style: .small, at: y, page: page)
                }
            }
        }
        return url
    }

    func textReport(session: DiagnosticSession) -> String {
        var lines = [
            "تقرير iDiagnostics",
            "جلسة: \(session.id.uuidString)",
            "الجهاز: \(session.device.marketingName)",
            "معرّف العتاد: \(session.device.modelIdentifier)",
            "النظام: \(session.device.systemName) \(session.device.systemVersion)",
            "وقت التقرير: \(dateFormatter.string(from: session.updatedAt))",
            "المؤشر: \(session.healthScore.map(String.init) ?? "غير محسوب") من 100",
            "الفحوص المكتملة: \(session.completedCount) من \(TestCategory.allCases.count)",
            "",
            "تنبيه: هذا تقرير إرشادي مبني على واجهات iOS العامة وتأكيد المستخدم، وليس تشخيصًا معتمدًا من Apple.",
            ""
        ]

        for category in TestCategory.allCases {
            let result = session.result(for: category)
            lines.append("\(category.titleAr): \(result.outcome.titleAr)")
            if !result.summaryAr.isEmpty { lines.append(result.summaryAr) }
            lines.append("مصدر النتيجة: \(result.evidence.titleAr)")
            for metric in result.metrics {
                lines.append("- \(metric.label): \(metric.value)")
            }
            if let limitation = result.limitationAr { lines.append("حدود الفحص: \(limitation)") }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    private func exportURL(session: DiagnosticSession, extension fileExtension: String) throws -> URL {
        let directory = fileManager.temporaryDirectory.appendingPathComponent("iDiagnostics-Exports", isDirectory: true)
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            throw ReportServiceError.cannotCreateExportDirectory
        }
        let shortID = session.id.uuidString.prefix(8)
        return directory.appendingPathComponent("iDiagnostics-\(shortID).\(fileExtension)")
    }

    @MainActor
    private func draw(_ text: String, style: PDFTextStyle, at y: CGFloat, page: CGRect) -> CGFloat {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .right
        paragraph.baseWritingDirection = .rightToLeft
        paragraph.lineBreakMode = .byWordWrapping
        let attributes: [NSAttributedString.Key: Any] = [
            .font: style.font,
            .foregroundColor: style.color,
            .paragraphStyle: paragraph
        ]
        let width = page.width - 84
        let attributed = NSAttributedString(string: text, attributes: attributes)
        let measured = attributed.boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        let height = ceil(measured.height) + style.spacing
        attributed.draw(with: CGRect(x: 42, y: y, width: width, height: height), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        return y + height
    }

    private func estimatedHeight(for result: DiagnosticResult) -> CGFloat {
        72 + CGFloat(result.metrics.count) * 24 + (result.limitationAr == nil ? 0 : 30)
    }
}

@MainActor
private enum PDFTextStyle {
    case title
    case heading
    case body
    case small

    var font: UIFont {
        switch self {
        case .title: return .boldSystemFont(ofSize: 24)
        case .heading: return .boldSystemFont(ofSize: 15)
        case .body: return .systemFont(ofSize: 12)
        case .small: return .systemFont(ofSize: 10)
        }
    }

    var color: UIColor {
        switch self {
        case .small: return .darkGray
        default: return .black
        }
    }

    var spacing: CGFloat {
        switch self {
        case .title: return 10
        case .heading: return 7
        case .body: return 5
        case .small: return 5
        }
    }
}
