import Foundation
import UserNotifications
import Combine

@MainActor
final class StudyReminderService: ObservableObject {
    enum AuthorizationState: String {
        case unknown
        case denied
        case authorized
        case provisional

        var titleAr: String {
            switch self {
            case .unknown: return L("لم يُطلب الإذن")
            case .denied: return L("الإشعارات غير مسموحة")
            case .authorized: return L("الإشعارات مسموحة")
            case .provisional: return L("الإشعارات مسموحة مؤقتًا")
            }
        }
    }

    @Published private(set) var authorization: AuthorizationState = .unknown
    @Published var errorMessage: String?

    private let center = UNUserNotificationCenter.current()
    private let reminderID = "englishnova.daily-study"

    func refreshAuthorization() async {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized: authorization = .authorized
        case .provisional, .ephemeral: authorization = .provisional
        case .denied: authorization = .denied
        case .notDetermined: authorization = .unknown
        @unknown default: authorization = .unknown
        }
    }

    func requestAndSchedule(hour: Int, minute: Int) async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            await refreshAuthorization()
            guard granted else { return false }
            try await schedule(hour: hour, minute: minute)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func schedule(hour: Int, minute: Int) async throws {
        center.removePendingNotificationRequests(withIdentifiers: [reminderID])
        let content = UNMutableNotificationContent()
        content.title = "موعد إنجليزيتك اليوم"
        content.body = "خمس دقائق تكفي لفتح باب جديد. أكمل خطتك اليومية في EnglishNova."
        content.sound = .default
        let components = DateComponents(hour: hour, minute: minute)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(identifier: reminderID, content: content, trigger: trigger)
        try await center.add(request)
    }

    func cancel() {
        center.removePendingNotificationRequests(withIdentifiers: [reminderID])
    }
}
