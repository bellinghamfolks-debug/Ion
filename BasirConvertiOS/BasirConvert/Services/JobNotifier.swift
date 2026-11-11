import Foundation
import UserNotifications

/// Every notification Basir shows about a task, in one place.
///
/// Each task has exactly one notification (identifier `basir-<task id>`,
/// the same one the server's push uses), which is replaced as the task
/// moves on: working → progress → ready / finished / failed. So the list
/// never fills with stale percentages, and the last thing the person sees
/// is always true. A notification never goes backwards: once "ready" or
/// "finished" was shown, a late progress update is dropped.
enum JobNotifier {
    enum Phase: Int, Codable, Sendable {
        case working = 0
        case progress = 1
        case needsApp = 2
        case ready = 3
        case finished = 4
        case failed = 5

        var isFinal: Bool { self == .finished || self == .failed }
        var kind: String {
            switch self {
            case .working: return "working"
            case .progress: return "progress"
            case .needsApp: return "needs_app"
            case .ready: return "ready"
            case .finished: return "completed"
            case .failed: return "failed"
            }
        }
    }

    enum Work: String, Codable, Sendable {
        case conversion
        case summary
        case video
    }

    struct Message: Equatable, Sendable {
        var title: String
        var body: String
        var phase: Phase
    }

    private static let deliveredKey = "basir_notified_phases"
    private static let lock = NSLock()

    static func identifier(_ id: String) -> String { "basir-\(id)" }

    /// The setting in Settings › Notifications (on unless turned off). Read
    /// from UserDefaults so it also works when iOS wakes Basir in the
    /// background before any screen exists.
    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: "completion_notifications") as? Bool ?? true
    }

    // MARK: Texts (pure, tested)

    static func working(task: Work, title: String, percent: Int, uploading: Bool, arabic: Bool) -> Message {
        if uploading {
            return Message(
                title: title,
                body: arabic
                    ? "جارٍ رفع الملف: \(percent)٪. أبقِ بصير مفتوحًا حتى ينتهي الرفع. بعدها تستمر المعالجة حتى لو انتقلت إلى تطبيق آخر."
                    : "Uploading: \(percent)%. Keep Basir open until the upload finishes. Processing can then continue while you use another app.",
                phase: .working)
        }
        let what: String
        switch task {
        case .summary: what = arabic ? "جارٍ إعداد الملخص" : "Preparing the summary"
        case .video: what = arabic ? "جارٍ وصف الفيديو" : "Describing the video"
        case .conversion: what = arabic ? "جارٍ معالجة الملف" : "Processing the file"
        }
        let progress = percent > 0 ? (arabic ? " (\(percent)٪)" : " (\(percent)%)") : ""
        return Message(
            title: title,
            body: arabic
                ? "\(what)\(progress). يمكنك استخدام تطبيق آخر أثناء الانتظار. قد تتأخر تحديثات التقدم في الخلفية."
                : "\(what)\(progress). You can use another app while you wait. Background progress updates may be delayed.",
            phase: .working)
    }

    static func progress(task: Work, title: String, percent: Int, at date: Date, arabic: Bool) -> Message {
        let time = clock(date, arabic: arabic)
        let what: String
        switch task {
        case .summary: what = arabic ? "الملخص" : "Summary"
        case .video: what = arabic ? "وصف الفيديو" : "Video description"
        case .conversion: what = arabic ? "التحويل" : "Conversion"
        }
        return Message(
            title: title,
            body: arabic
                ? "\(what): \(percent)٪. العمل مستمر. آخر تحديث: \(time)."
                : "\(what): \(percent)%. Still in progress. Last updated: \(time).",
            phase: .progress)
    }

    static func uploadNeedsApp(title: String, percent: Int, arabic: Bool) -> Message {
        Message(
            title: title,
            body: arabic
                ? "توقف رفع الملف مؤقتًا عند \(percent)٪ أثناء عمل بصير في الخلفية. افتح بصير لاستكمال الرفع وبدء المعالجة."
                : "The upload paused at \(percent)% while Basir was in the background. Open Basir to finish uploading and start processing.",
            phase: .needsApp)
    }

    static func ready(task: Work, title: String, arabic: Bool) -> Message {
        Message(
            title: title,
            body: task == .summary
                ? (arabic ? "الملخص جاهز. افتح بصير لقراءته." : "The summary is ready. Open Basir to read it.")
                : task == .video
                ? (arabic ? "وصف الفيديو جاهز. افتح بصير لسماعه." : "The video description is ready. Open Basir to hear it.")
                : (arabic ? "ملف Word جاهز. افتح بصير ليحفظه على جهازك." : "The Word file is ready. Open Basir to save it to your iPhone."),
            phase: .ready)
    }

    static func finished(task: Work, title: String, partial: Bool, arabic: Bool) -> Message {
        let body: String
        switch (task, partial) {
        case (.summary, _):
            body = arabic ? "الملخص جاهز للقراءة." : "The summary is ready to read."
        case (.video, _):
            body = arabic ? "وصف الفيديو جاهز للسماع." : "The video description is ready to hear."
        case (.conversion, false):
            body = arabic ? "اكتمل التحويل. ستجد ملف Word في «ملفاتي»." : "Done. The Word file is saved in My Files."
        case (.conversion, true):
            body = arabic ? "الملف جاهز، لكن بعض الصفحات تحتاج إلى مراجعة. افتح بصير للاطلاع عليها وإعادة محاولة قراءتها."
                          : "The file is ready, but some pages need review. Open Basir to check them and try reading them again."
        }
        return Message(title: title, body: body, phase: .finished)
    }

    static func failed(title: String, reason: String?, arabic: Bool) -> Message {
        let detail = reason.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.isEmpty ? nil : $0 }
        let tail = arabic ? "افتح بصير لإعادة المحاولة." : "Open Basir to try again."
        return Message(
            title: title,
            body: detail.map { "\($0) \(tail)" } ?? ((arabic ? "لم تكتمل المهمة. " : "The task did not complete. ") + tail),
            phase: .failed)
    }

    /// Whether a new message may replace what was already shown.
    static func allows(_ next: Phase, after previous: Phase?) -> Bool {
        guard let previous else { return true }
        if previous.isFinal { return false }
        // "Still working" is said once per task. Leaving Basir again and
        // again must not repeat it; real progress arrives as `.progress`.
        if next == .working { return false }
        if previous == .ready { return next.isFinal }
        return true
    }

    static func clock(_ date: Date, arabic: Bool) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: arabic ? "ar" : "en")
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    // MARK: Delivery

    /// Shows (or replaces) the task's one notification.
    static func show(_ message: Message, id: String, openJob: UUID? = nil) {
        guard isEnabled else { return }
        lock.lock()
        var delivered = deliveredPhases()
        let previous = delivered[id].flatMap(Phase.init(rawValue:))
        guard allows(message.phase, after: previous) else {
            lock.unlock()
            return
        }
        delivered[id] = message.phase.rawValue
        UserDefaults.standard.set(delivered, forKey: deliveredKey)
        lock.unlock()

        let content = UNMutableNotificationContent()
        content.title = message.title
        content.body = message.body
        content.threadIdentifier = "basir-job-\(id)"
        var info: [String: String] = ["basir_kind": message.phase.kind]
        if let openJob { info["job_id"] = openJob.uuidString }
        content.userInfo = info
        switch message.phase {
        case .working, .progress:
            // On the Lock Screen and in Notification Center, without a sound
            // or waking the screen every quarter.
            content.interruptionLevel = .passive
        case .needsApp, .ready, .finished, .failed:
            content.interruptionLevel = .active
            content.sound = .default
        }
        content.relevanceScore = Double(message.phase.rawValue + 1) / 6
        let request = UNNotificationRequest(identifier: identifier(id), content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                DiagnosticLogger.recordGlobal("NOTIFY failed id=\(id) phase=\(message.phase.kind) description=\(error.localizedDescription)")
            }
        }
    }

    /// A task starts (or starts again): forget what was shown for it.
    static func reset(_ id: String) {
        lock.lock()
        var delivered = deliveredPhases()
        delivered.removeValue(forKey: id)
        // Keep the record small: it only matters for tasks still in flight.
        if delivered.count > 200 { delivered = [:] }
        UserDefaults.standard.set(delivered, forKey: deliveredKey)
        lock.unlock()
    }

    /// Removes the task's notification (after a cancellation).
    static func remove(_ id: String) {
        let center = UNUserNotificationCenter.current()
        center.removeDeliveredNotifications(withIdentifiers: [identifier(id)])
        center.removePendingNotificationRequests(withIdentifiers: [identifier(id)])
        reset(id)
    }

    /// Settings › Notifications › Send a test notification.
    static func sendTest(arabic: Bool) {
        let content = UNMutableNotificationContent()
        content.title = arabic ? "بصير" : "Basir"
        content.body = arabic ? "هذا إشعار تجريبي من بصير." : "This is a test notification from Basir."
        content.sound = .default
        content.interruptionLevel = .active
        content.userInfo = ["basir_kind": "test"]
        // A few seconds later, so it also shows when the app is closed at once.
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 3, repeats: false)
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "basir-test", content: content,
                                                                     trigger: trigger))
    }

    private static func deliveredPhases() -> [String: Int] {
        UserDefaults.standard.dictionary(forKey: deliveredKey) as? [String: Int] ?? [:]
    }
}
