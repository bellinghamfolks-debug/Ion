import Foundation
import UIKit
import UserNotifications

/// Local notifications: "your drink is ready" and machine alerts while the
/// app is in the background (Bluetooth keeps running there), plus optional
/// care reminders.
@MainActor
final class NotificationManager {
    static let shared = NotificationManager()

    private let center = UNUserNotificationCenter.current()

    enum Reminder: String, CaseIterable, Identifiable {
        case brewingUnitWeekly, carafeDaily, filterMonthly
        var id: String { rawValue }
    }

    @discardableResult
    func requestPermission() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    private var inBackground: Bool { UIApplication.shared.applicationState != .active }

    func drinkFinished(_ recipe: Recipe) {
        guard inBackground else { return }
        post(id: "drink-ready", title: L("notify.ready.title"), body: L("announce.brewFinished", recipe.displayName))
    }

    func alarms(_ alarms: [MachineAlarm]) {
        guard inBackground, !alarms.isEmpty else { return }
        post(id: "alarm-\(alarms.map(\.rawValue).joined(separator: "-"))",
             title: L("notify.alarm.title"),
             body: alarms.map(\.title).joined(separator: L("list.separator")))
    }

    func schedule(_ reminder: Reminder, enabled: Bool, hour: Int = 9) {
        center.removePendingNotificationRequests(withIdentifiers: [reminder.rawValue])
        guard enabled else { return }
        var components = DateComponents()
        components.hour = hour
        components.minute = 0
        switch reminder {
        case .brewingUnitWeekly: components.weekday = 6          // Friday
        case .carafeDaily: components.hour = 20
        case .filterMonthly: components.day = 1
        }
        let content = UNMutableNotificationContent()
        content.title = L("reminder.\(reminder.rawValue).title")
        content.body = L("reminder.\(reminder.rawValue).body")
        content.sound = .default
        let request = UNNotificationRequest(identifier: reminder.rawValue, content: content,
                                            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true))
        center.add(request)
    }

    private func post(id: String, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }
}
