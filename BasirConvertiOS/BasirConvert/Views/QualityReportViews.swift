import SwiftUI

/// Five named steps with clear done / current / waiting states.
struct JobStepTimeline: View {
    @EnvironmentObject private var l10n: L10n
    let progress: ConversionProgress
    var finished = false

    var body: some View {
        let current = finished ? nil : JobStep.current(for: progress)
        VStack(alignment: .leading, spacing: BasirSpacing.s) {
            ForEach(JobStep.allCases) { step in
                let state = stepState(step, current: current)
                HStack(spacing: BasirSpacing.m) {
                    Image(systemName: state.icon)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(state.color)
                        .frame(width: 28)
                        .accessibilityHidden(true)
                    Text(step.title(l10n))
                        .font(.body.weight(state == .current ? .bold : .regular))
                        .foregroundStyle(state == .waiting ? BasirPalette.tertiaryText : BasirPalette.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    if state == .current, let fraction = JobStep.stepFraction(for: progress) {
                        Text("\(Int((fraction * 100).rounded()))%")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(BasirPalette.secondaryText)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(l10n.t("الخطوة \(step.rawValue + 1) من 5: \(step.title(l10n))",
                                           "Step \(step.rawValue + 1) of 5: \(step.title(l10n))"))
                .accessibilityValue(state.spoken(l10n))
            }
        }
    }

    private enum StepState: Equatable {
        case done, current, waiting

        var icon: String {
            switch self {
            case .done: return "checkmark.circle.fill"
            case .current: return "circle.dotted.circle"
            case .waiting: return "circle"
            }
        }

        var color: Color {
            switch self {
            case .done: return BasirPalette.success
            case .current: return BasirPalette.accent
            case .waiting: return BasirPalette.tertiaryText
            }
        }

        @MainActor
        func spoken(_ l10n: L10n) -> String {
            switch self {
            case .done: return l10n.t("مكتملة", "Done")
            case .current: return l10n.t("قيد التنفيذ", "In progress")
            case .waiting: return l10n.t("لم تبدأ", "Not started")
            }
        }
    }

    private func stepState(_ step: JobStep, current: JobStep?) -> StepState {
        guard let current else { return .done }
        if step.rawValue < current.rawValue { return .done }
        if step == current { return .current }
        return .waiting
    }
}

/// One-line summary of the verification result, used on result cards.
struct QualityBadge: View {
    @EnvironmentObject private var l10n: L10n
    let report: QualityReport

    var body: some View {
        Label(text, systemImage: report.hasConcerns ? "checkmark.shield" : "checkmark.shield.fill")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(report.hasConcerns ? BasirPalette.warning : BasirPalette.success)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var text: String {
        if report.hasConcerns {
            return l10n.t("اكتمل الفحص مع ملاحظات", "Checked with notes")
        }
        return l10n.t("اكتمل فحص الجودة", "Quality check complete")
    }
}

/// The server quality manifest and the app's own Word check, in plain words.
struct QualityReportCard: View {
    @EnvironmentObject private var l10n: L10n
    let report: QualityReport

    var body: some View {
        VStack(alignment: .leading, spacing: BasirSpacing.m) {
            GlassSectionTitle(title: l10n.t("تقرير الجودة", "Quality report"),
                              systemImage: report.hasConcerns ? "checkmark.shield" : "checkmark.shield.fill")
            Text(headline)
                .font(.body.weight(.semibold))
                .foregroundStyle(report.hasConcerns ? BasirPalette.warning : BasirPalette.success)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(lines, id: \.self) { line in
                HStack(alignment: .top, spacing: BasirSpacing.s) {
                    Image(systemName: line.icon)
                        .foregroundStyle(line.isConcern ? BasirPalette.warning : BasirPalette.accent)
                        .frame(width: 22)
                        .accessibilityHidden(true)
                    Text(line.text)
                        .font(.subheadline)
                        .foregroundStyle(BasirPalette.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .glassSurface(accent: report.hasConcerns ? BasirPalette.warning : BasirPalette.success)
    }

    private var headline: String {
        if let score = report.percentScore {
            return report.hasConcerns
                ? l10n.t("تقييم الفحص الآلي: \(score) من 100. توجد ملاحظات للمراجعة.",
                         "Automated check score: \(score) out of 100. Review the notes below.")
                : l10n.t("تقييم الفحص الآلي: \(score) من 100.",
                         "Automated check score: \(score) out of 100.")
        }
        return report.hasConcerns
            ? l10n.t("اكتمل فحص الملف. راجع الملاحظات التالية.", "The file check is complete. Review the notes below.")
            : l10n.t("اكتمل فحص الملف دون ملاحظات.", "The file check is complete with no issues reported.")
    }

    private struct Line: Hashable {
        let icon: String
        let text: String
        var isConcern = false
    }

    private var lines: [Line] {
        var result: [Line] = []
        if let pages = report.sourcePages, pages > 0 {
            result.append(Line(icon: "doc.on.doc",
                               text: l10n.t("الصفحات المحفوظة في النتيجة: \(report.retainedPages) من \(pages).",
                                            "Pages included in the result: \(report.retainedPages) of \(pages).")))
        } else if report.retainedPages > 0 {
            result.append(Line(icon: "doc.on.doc",
                               text: l10n.t("الصفحات المحفوظة في النتيجة: \(report.retainedPages).", "Pages included in the result: \(report.retainedPages).")))
        }
        if report.skippedBlankPages > 0 {
            result.append(Line(icon: "doc",
                               text: l10n.t("الصفحات الفارغة التي جرى تخطيها: \(report.skippedBlankPages).",
                                            "Blank pages skipped: \(report.skippedBlankPages).")))
        }
        if report.fallbackPages > 0 {
            result.append(Line(icon: "photo.on.rectangle",
                               text: l10n.t("صفحات حُفظت كصور مع وصف نصي لتعذر قراءة نصها بوضوح: \(report.fallbackPages). يمكنك إعادة محاولة معالجتها.",
                                            "Pages saved as images with text descriptions because their text could not be read clearly: \(report.fallbackPages). You can retry them."),
                               isConcern: true))
        }
        if report.tables > 0 {
            result.append(Line(icon: "tablecells",
                               text: l10n.t("الجداول القابلة للتنقل بقارئ الشاشة: \(report.tables).",
                                            "Tables you can navigate with a screen reader: \(report.tables).")))
        }
        if report.images > 0 {
            if report.imagesMissingDescription == 0 {
                result.append(Line(icon: "text.below.photo",
                                   text: l10n.t("جميع الصور لها وصف نصي. عدد الصور: \(report.images).",
                                                "All images have text descriptions. Total images: \(report.images).")))
            } else {
                result.append(Line(icon: "text.below.photo",
                                   text: l10n.t("الصور التي لا يتوفر لها وصف نصي: \(report.imagesMissingDescription) من \(report.images).",
                                                "Images without text descriptions: \(report.imagesMissingDescription) of \(report.images)."),
                                   isConcern: true))
            }
        }
        if report.textCharacters > 0 {
            let words = max(1, report.textCharacters / 6)
            result.append(Line(icon: "text.alignleft",
                               text: l10n.t("عدد الكلمات التقريبي: \(words).", "Approximate word count: \(words).")))
        }
        if report.wordPackageVerified {
            result.append(Line(icon: "checkmark.seal",
                               text: l10n.t("اجتاز ملف Word فحص سلامة الملف على جهازك قبل حفظه.",
                                            "The Word file passed an integrity check on your device before it was saved.")))
        }
        for warning in report.warnings.prefix(5) {
            result.append(Line(icon: "exclamationmark.triangle", text: Self.describe(warning, l10n: l10n), isConcern: true))
        }
        return result
    }

    /// Turns a server warning code such as "low_contrast_pages" into words.
    @MainActor
    static func describe(_ code: String, l10n: L10n) -> String {
        let known: [String: (String, String)] = [
            "low_confidence_pages": ("قد تحتوي بعض الصفحات على أخطاء في قراءة النص. يُنصح بمراجعتها.", "Text recognition may be less accurate on some pages. Please review them."),
            "handwriting_detected": ("يحتوي المستند على خط يد؛ راجع تلك المواضع.", "The document contains handwriting; review those parts."),
            "fallback_pages": ("بعض الصفحات حُفظت كصور موصوفة.", "Some pages were kept as described images."),
            "missing_alt_text": ("بعض الصور ليس لها وصف نصي.", "Some images have no text description."),
            "relaxed_layout": ("بُسّط تخطيط بعض الصفحات للحفاظ على النص.", "Some page layouts were simplified to preserve the text.")
        ]
        let key = code.lowercased()
        if let match = known[key] { return l10n.t(match.0, match.1) }
        let readable = code.replacingOccurrences(of: "_", with: " ")
        return l10n.t("ملاحظة في تقرير الجودة: \(readable)", "Quality report note: \(readable)")
    }
}
