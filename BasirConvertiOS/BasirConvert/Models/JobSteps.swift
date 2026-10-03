import Foundation

/// The five steps a person sees for every task, in order. They are derived
/// from the transport stages so the server contract stays unchanged.
enum JobStep: Int, CaseIterable, Identifiable, Codable, Hashable, Sendable {
    case upload
    case read
    case verify
    case writeWord
    case download

    var id: Int { rawValue }

    @MainActor
    func title(_ l10n: L10n) -> String {
        switch self {
        case .upload: return l10n.t("رفع", "Upload")
        case .read: return l10n.t("قراءة", "Read")
        case .verify: return l10n.t("تحقق", "Verify")
        case .writeWord: return l10n.t("كتابة Word", "Write Word")
        case .download: return l10n.t("تنزيل", "Download")
        }
    }

    @MainActor
    func activeTitle(_ l10n: L10n) -> String {
        switch self {
        case .upload: return l10n.t("جارٍ رفع الملف", "Uploading the file")
        case .read: return l10n.t("جارٍ قراءة المحتوى", "Reading the content")
        case .verify: return l10n.t("جارٍ التحقق من الجودة", "Verifying quality")
        case .writeWord: return l10n.t("جارٍ كتابة ملف Word", "Writing the Word file")
        case .download: return l10n.t("جارٍ تنزيل النتيجة", "Downloading the result")
        }
    }

    var systemImage: String {
        switch self {
        case .upload: return "arrow.up.doc"
        case .read: return "text.viewfinder"
        case .verify: return "checkmark.shield"
        case .writeWord: return "doc.richtext"
        case .download: return "arrow.down.doc"
        }
    }

    /// Share of the whole task each step represents, used for one overall
    /// percentage that never moves backwards between steps.
    private var weight: Double {
        switch self {
        case .upload: return 0.10
        case .read: return 0.70
        case .verify: return 0.08
        case .writeWord: return 0.04
        case .download: return 0.08
        }
    }

    /// The step a progress update belongs to, or nil once the task is done.
    static func current(for progress: ConversionProgress) -> JobStep? {
        switch progress.stage {
        case .preparing, .uploading, .waitingForNetwork:
            return .upload
        case .processing:
            if progress.total > 0, progress.current >= progress.total { return .verify }
            return .read
        case .paused:
            return progress.current > 0 ? .read : .upload
        case .finalising:
            return .writeWord
        case .downloading:
            return .download
        case .done:
            return nil
        }
    }

    /// Progress inside the current step, when it is measurable.
    static func stepFraction(for progress: ConversionProgress) -> Double? {
        guard let step = current(for: progress) else { return 1 }
        switch step {
        case .upload, .download:
            guard progress.totalBytes > 0 else { return nil }
            return min(1, max(0, Double(progress.transferredBytes) / Double(progress.totalBytes)))
        case .read:
            return progress.fraction
        case .verify, .writeWord:
            return nil
        }
    }

    /// Overall completion from 0 to 100.
    static func overallPercent(for progress: ConversionProgress) -> Int {
        guard let step = current(for: progress) else { return 100 }
        let completed = JobStep.allCases.filter { $0.rawValue < step.rawValue }.reduce(0) { $0 + $1.weight }
        let inside = (stepFraction(for: progress) ?? 0) * step.weight
        return min(99, max(0, Int(((completed + inside) * 100).rounded(.down))))
    }

    /// One sentence for VoiceOver and the Live Activity, for example
    /// "Reading the content, page 3 of 10, 31 percent".
    @MainActor
    static func spokenStatus(for progress: ConversionProgress, l10n: L10n) -> String {
        guard let step = current(for: progress) else {
            return l10n.t("اكتملت المهمة", "Task complete")
        }
        var parts = [step.activeTitle(l10n)]
        if step == .read, progress.total > 0 {
            parts.append(l10n.t("الصفحة \(progress.current) من \(progress.total)",
                                "page \(progress.current) of \(progress.total)"))
        }
        let percent = overallPercent(for: progress)
        parts.append(l10n.t("\(percent) بالمئة", "\(percent) percent"))
        return parts.joined(separator: l10n.isArabic ? "، " : ", ")
    }
}
