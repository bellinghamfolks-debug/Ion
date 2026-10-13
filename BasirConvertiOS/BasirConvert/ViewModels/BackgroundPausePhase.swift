import Foundation

/// Where a task was when iOS stopped the app in the background, which
/// decides what is true to tell the person.
enum BackgroundPausePhase: Equatable {
    /// The file had not finished uploading: nothing happens until Basir opens.
    case uploading
    /// The server has the file and is converting it without the app.
    case serverWorking
    /// The server finished; only saving the result to the iPhone remains.
    case serverFinished

    init(stage: ConversionStage) {
        switch stage {
        case .preparing, .waitingForNetwork, .uploading, .paused: self = .uploading
        case .processing, .finalising: self = .serverWorking
        case .downloading, .done: self = .serverFinished
        }
    }

    @MainActor
    func statusMessage(l10n: L10n) -> String {
        switch self {
        case .uploading:
            return l10n.t("أوقف النظام رفع الملف مؤقتًا أثناء عمل بصير في الخلفية. افتح التطبيق لاستكمال الرفع.",
                          "The system paused the upload while Basir was in the background. Open the app to continue uploading.")
        case .serverWorking:
            return l10n.t("المعالجة مستمرة على خادم بصير. عند فتح التطبيق، سيتابع تقدم المهمة ويُنزّل النتيجة عند جاهزيتها.",
                          "Processing continues on Basir’s server. When you open the app, it will check progress and download the result when ready.")
        case .serverFinished:
            return l10n.t("ملف Word جاهز. افتح بصير لتنزيله على جهازك.",
                          "Your Word file is ready. Open Basir to download it to your device.")
        }
    }

    @MainActor
    func notificationBody(percent: Int, l10n: L10n) -> String {
        switch self {
        case .uploading:
            return l10n.t("توقف رفع الملف مؤقتًا عند \(percent)٪ أثناء عمل التطبيق في الخلفية. افتح بصير لاستكمال الرفع.",
                          "The upload paused at \(percent)% while the app was in the background. Open Basir to continue.")
        case .serverWorking:
            return l10n.t("المعالجة مستمرة على خادم بصير. التقدم: \(percent)٪.",
                          "Processing continues on Basir’s server. Progress: \(percent)%.")
        case .serverFinished:
            return l10n.t("ملف Word جاهز. افتح بصير لحفظه على جهازك.",
                          "The Word file is ready. Open Basir to save it to your iPhone.")
        }
    }
}
