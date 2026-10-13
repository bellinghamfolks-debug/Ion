import Foundation

/// Turns any error the app can meet into plain, actionable words in the
/// person's language.
@MainActor
enum ErrorLocalizer {
    /// Errors that mean "wait for the network" rather than "failed".
    nonisolated static func isNetworkWait(_ error: Error) -> Bool {
        if error is URLError { return true }
        guard let basir = error as? BasirError else { return false }
        switch basir {
        case .networkUnavailable, .wifiRequired, .constrainedNetwork:
            return true
        default:
            return false
        }
    }

    /// The message a person reads or hears for an error.
    static func message(for error: Error, l10n: L10n) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost:
                return l10n.t("انقطع الاتصال بالإنترنت. ستُستأنف المهمة عند عودة الاتصال.",
                              "The internet connection was lost. The task will resume when you’re connected again.")
            case .timedOut:
                return l10n.t("استغرقت الخدمة وقتًا طويلًا للرد. حاول مرة أخرى.", "The service took too long to respond. Try again.")
            case .cannotFindHost, .dnsLookupFailed:
                return l10n.t("تعذر الوصول إلى خدمة بصير. تحقق من اتصالك وحاول مرة أخرى.", "Could not reach Basir. Check your connection and try again.")
            case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate:
                return l10n.t("تعذر الاتصال بالخدمة بأمان. تحقق من اتصالك وإعدادات التاريخ والوقت.",
                              "Could not connect securely. Check your connection and your device’s date and time settings.")
            default:
                return l10n.t("تعذر الاتصال بالشبكة: \(urlError.localizedDescription)",
                              "Network error: \(urlError.localizedDescription)")
            }
        }
        guard let basir = error as? BasirError else {
            return l10n.t("تعذر إكمال المهمة: \(error.localizedDescription)",
                          "Could not complete the task: \(error.localizedDescription)")
        }
        switch basir {
        case .notConfigured:
            return l10n.t("خدمة المعالجة غير مهيأة في هذه النسخة. تواصل مع فريق بصير.",
                          "Processing is not set up in this version. Contact the Basir team.")
        case .unsupportedFile:
            return l10n.t("نوع الملف غير مدعوم لهذه المهمة.", "This file type is not supported for this task.")
        case .invalidFileContent:
            return l10n.t("محتوى الملف لا يطابق صيغته. احفظ نسخة جديدة من التطبيق الأصلي ثم أعد المحاولة.",
                          "The file’s content does not match its format. Save a new copy from the original app, then try again.")
        case .emptyDocument:
            return l10n.t("لا يحتوي الملف على محتوى قابل للقراءة.", "The file contains no readable content.")
        case .noReadablePages:
            return l10n.t("تعذرت قراءة صفحات الملف. تحقق من وضوحها ثم أعد المحاولة.", "The file’s pages could not be read. Check their clarity, then try again.")
        case .invalidServerURL:
            return l10n.t("تعذر إنشاء اتصال آمن بالخدمة.",
                          "A secure service connection could not be created.")
        case .fileTooLarge:
            let limit = FileAccess.maximumSourceBytes / (1024 * 1024)
            return l10n.t("حجم الملف أكبر من الحد المسموح وهو \(limit) ميجابايت.",
                          "The file is larger than the \(limit) MB limit.")
        case .tooManyImages(let count, let limit):
            return l10n.t("عدد الصور \(count)، والحد الأقصى في ملف واحد \(limit) صورة. قسّمها على أكثر من ملف.",
                          "That is \(count) images; one file can hold up to \(limit). Split them across more than one file.")
        case .networkUnavailable:
            return l10n.t("لا يوجد اتصال بالإنترنت. المهمة محفوظة في قائمة الانتظار.",
                          "No internet connection. Your task is saved in the queue.")
        case .wifiRequired:
            return l10n.t("المهمة بانتظار Wi‑Fi وفق إعداداتك. اتصل بشبكة Wi‑Fi أو غيّر خيار الاتصال في الإعدادات.",
                          "Your settings require Wi-Fi. Connect to Wi-Fi or change the connection option in Settings.")
        case .constrainedNetwork:
            return l10n.t("المهمة متوقفة بسبب وضع البيانات المنخفضة. يمكنك السماح بالمعالجة في هذا الوضع من إعدادات بصير.",
                          "Low Data Mode is preventing this task from running. You can allow processing in this mode in Basir’s settings.")
        case .authenticationFailed:
            return l10n.t("تعذر التحقق من صلاحية الوصول إلى الخدمة. حدّث التطبيق، أو تواصل مع فريق بصير إذا استمرت المشكلة.",
                          "Could not verify access to the service. Update the app, or contact the Basir team if the issue continues.")
        case .rateLimited(let seconds):
            return seconds.map {
                l10n.t("الخدمة مشغولة. أعد المحاولة بعد \(Int($0)) ثانية.",
                       "The service is busy. Retry after \(Int($0)) seconds.")
            } ?? l10n.t("الخدمة مشغولة الآن. حاول مرة أخرى بعد قليل.", "The service is busy. Please try again shortly.")
        case .invalidServerContentType:
            return l10n.t("لم يصل ملف Word المتوقع. أعد المحاولة لتنزيل النتيجة.",
                          "The expected Word file was not received. Try downloading the result again.")
        case .checksumMismatch:
            return l10n.t("تعذر التأكد من سلامة الملف المنزّل. أعد المحاولة لتنزيله مجددًا.", "The downloaded file could not be verified. Try downloading it again.")
        case .passwordProtectedPDF:
            return l10n.t("ملف PDF محمي بكلمة مرور. افتحه واحفظ نسخة غير محمية أولًا.",
                          "The PDF is password protected. Open it and save an unlocked copy first.")
        case .invalidPageSelection:
            return l10n.t("راجع أرقام الصفحات المطلوبة. أدخلها مثل: 1-20، 25، 30-40.",
                          "Check the requested page numbers. Use a format such as 1-20, 25, 30-40.")
        case .invalidResponse:
            return l10n.t("تعذر التحقق من النتيجة التي أرسلتها الخدمة. حاول مرة أخرى.", "Could not verify the result returned by the service. Try again.")
        case .conversionFailed(let message):
            if message.contains("401") || message.contains("403") {
                return l10n.t("تعذر التحقق من صلاحية الوصول إلى الخدمة. تواصل مع فريق بصير إذا استمرت المشكلة.", "Could not verify access to the service. Contact the Basir team if the issue continues.")
            }
            if message.contains("429") {
                return l10n.t("الخدمة مشغولة أو بلغ حسابك الحد المؤقت للطلبات. حاول لاحقًا.",
                              "The service is busy or your account has reached a temporary request limit. Try again later.")
            }
            return l10n.t("تعذر إكمال المهمة. أعد المحاولة لمتابعتها من آخر تقدم محفوظ.",
                          "Could not complete the task. Try again to continue from the last saved progress.")
        }
    }
}
