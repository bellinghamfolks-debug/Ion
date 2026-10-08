import Foundation
import PDFKit
import AVFoundation
import ZIPFoundation

/// What Basir expects before a task starts: how much content there is, what
/// kind it is, and roughly how long it will take. Computed on the device;
/// the time is an honest range, not a promise.
struct TaskEstimate: Equatable, Sendable {
    enum Content: Equatable, Sendable {
        case textPDF, scannedPDF, mixedPDF, images, presentation, word, audio
    }

    let content: Content
    /// Pages, slides, images, or audio minutes.
    let units: Int
    let seconds: ClosedRange<Int>

    /// Long documents are worth narrowing to the pages actually needed.
    var suggestsPageSelection: Bool {
        (content == .textPDF || content == .scannedPDF || content == .mixedPDF) && units > 40
    }

    @MainActor
    func sentence(_ l10n: L10n) -> String {
        let what: String
        switch content {
        case .textPDF: what = l10n.t("PDF نصي من \(units) صفحة", "a \(units)-page text PDF")
        case .scannedPDF: what = l10n.t("PDF ممسوح ضوئيًا من \(units) صفحة", "a \(units)-page scanned PDF")
        case .mixedPDF: what = l10n.t("PDF من \(units) صفحة، بعضها ممسوح ضوئيًا", "a \(units)-page PDF, partly scanned")
        case .images: what = l10n.t("\(units) من الصور", "\(units) image(s)")
        case .presentation: what = l10n.t("عرض من \(units) شريحة", "a \(units)-slide presentation")
        case .word: what = l10n.t("مستند Word", "a Word document")
        case .audio: what = l10n.t("تسجيل مدته نحو \(units) دقيقة", "a recording of about \(units) minute(s)")
        }
        return l10n.t("هذا \(what). الوقت المتوقع \(Self.duration(seconds, l10n: l10n)) تقريبًا، بعد الرفع.",
                      "This is \(what). Expected time: about \(Self.duration(seconds, l10n: l10n)), after upload.")
    }

    @MainActor
    static func duration(_ range: ClosedRange<Int>, l10n: L10n) -> String {
        func minutes(_ value: Int) -> Int { max(1, Int((Double(value) / 60).rounded())) }
        let low = minutes(range.lowerBound), high = minutes(range.upperBound)
        if high <= 1 { return l10n.t("أقل من دقيقتين", "under two minutes") }
        if low == high { return l10n.t("\(low) دقائق", "\(low) minutes") }
        return l10n.t("من \(low) إلى \(high) دقائق", "\(low) to \(high) minutes")
    }
}

enum TaskEstimator {
    /// Server-side pages handled at the same time (matches the engine).
    static let concurrentPages = 8
    /// Starting a worker, writing the Word file and downloading it.
    static let fixedOverheadSeconds = 45

    static func estimate(url: URL, operation: OperationKind, selectedPages: Int? = nil) -> TaskEstimate? {
        let ext = url.pathExtension.lowercased()
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        if ext == "pdf" {
            guard let pdf = PDFDocument(url: url) else { return nil }
            let total = selectedPages ?? pdf.pageCount
            let content = pdfContent(pdf)
            return TaskEstimate(content: content, units: total,
                                seconds: seconds(units: total, content: content, operation: operation))
        }
        if SupportedInput.imageExtensions.contains(ext) {
            return TaskEstimate(content: .images, units: 1, seconds: seconds(units: 1, content: .images, operation: operation))
        }
        if ext == "pptx" {
            let slides = slideCount(url) ?? 10
            return TaskEstimate(content: .presentation, units: slides,
                                seconds: seconds(units: slides, content: .presentation, operation: operation))
        }
        if ext == "docx" || ext == "doc" {
            return TaskEstimate(content: .word, units: 1, seconds: seconds(units: 1, content: .word, operation: operation))
        }
        let asset = AVURLAsset(url: url)
        let minutes = Int((CMTimeGetSeconds(asset.duration) / 60).rounded(.up))
        guard minutes > 0 else { return nil }
        return TaskEstimate(content: .audio, units: minutes, seconds: seconds(units: minutes, content: .audio, operation: operation))
    }

    /// Model time per page, by kind, from field measurements; a range
    /// because pages differ (tables, handwriting and images take longer).
    static func seconds(units: Int, content: TaskEstimate.Content, operation: OperationKind) -> ClosedRange<Int> {
        let perUnit: ClosedRange<Double>
        var parallel = Double(concurrentPages)
        switch content {
        case .textPDF: perUnit = 6...14
        case .mixedPDF: perUnit = 8...20
        case .scannedPDF, .images: perUnit = 10...26
        case .presentation: perUnit = 4...10; parallel = 4
        case .word: perUnit = 20...60; parallel = 1
        case .audio:
            // 20-minute segments, three at a time, each about 1 to 3 minutes.
            let segments = Double(max(1, Int((Double(units) / 20).rounded(.up))))
            let rounds = (segments / 3).rounded(.up)
            return (fixedOverheadSeconds + Int(rounds * 60))...(fixedOverheadSeconds + Int(rounds * 180))
        }
        let factor = operation == .translate ? 1.3 : 1.0
        let rounds = (Double(max(1, units)) / parallel).rounded(.up)
        let low = fixedOverheadSeconds + Int(rounds * perUnit.lowerBound * factor)
        let high = fixedOverheadSeconds + Int(rounds * perUnit.upperBound * factor)
        return low...max(low, high)
    }

    /// Samples up to 12 pages spread through the document for a text layer.
    static func pdfContent(_ pdf: PDFDocument) -> TaskEstimate.Content {
        let count = pdf.pageCount
        guard count > 0 else { return .textPDF }
        let step = max(1, count / 12)
        var withText = 0, sampled = 0
        for index in stride(from: 0, to: count, by: step).prefix(12) {
            sampled += 1
            let text = pdf.page(at: index)?.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if text.count >= 40 { withText += 1 }
        }
        if withText == sampled { return .textPDF }
        if withText == 0 { return .scannedPDF }
        return .mixedPDF
    }

    static func slideCount(_ url: URL) -> Int? {
        guard let archive = try? Archive(url: url, accessMode: .read) else { return nil }
        let slides = archive.filter { $0.path.hasPrefix("ppt/slides/slide") && $0.path.hasSuffix(".xml") }.count
        return slides > 0 ? slides : nil
    }
}
