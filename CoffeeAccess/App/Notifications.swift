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
        post(id: "drink-ready", title: L("notify.ready.title"), body: L("announce.brewFinished", recipe.displayName),
             category: Self.readyCategory, userInfo: ["again": recipe.id.uuidString])
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

    private func post(id: String, title: String, body: String, category: String? = nil, userInfo: [String: String] = [:]) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if let category { content.categoryIdentifier = category }
        content.userInfo = userInfo
        content.interruptionLevel = .timeSensitive
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }
}

// MARK: - Version 2: scheduled drinks, care forecast, carafe and summaries

extension NotificationManager {
    static let brewCategory = "BREW_SCHEDULED"
    static let brewAction = "BREW_NOW"
    static let carafeID = "carafe-rinse"

    static let carafeCategory = "CARAFE"
    static let carafeAction = "CARAFE_CLEANED"
    static let readyCategory = "DRINK_READY"
    static let againAction = "BREW_AGAIN"
    static let leftOnCategory = "LEFT_ON"
    static let turnOffAction = "TURN_OFF"

    /// Actions on notifications: make a scheduled drink now, mark the carafe
    /// cleaned, make the same drink again, turn the machine off.
    func registerCategories() {
        let brew = UNNotificationAction(identifier: Self.brewAction, title: L("schedule.notify.action"), options: [.foreground])
        let cleaned = UNNotificationAction(identifier: Self.carafeAction, title: L("carafe.cleaned"), options: [])
        let again = UNNotificationAction(identifier: Self.againAction, title: L("notify.again"), options: [.foreground])
        let off = UNNotificationAction(identifier: Self.turnOffAction, title: L("leftOn.turnOff"), options: [.foreground])
        UNUserNotificationCenter.current().setNotificationCategories([
            UNNotificationCategory(identifier: Self.brewCategory, actions: [brew], intentIdentifiers: []),
            UNNotificationCategory(identifier: Self.carafeCategory, actions: [cleaned], intentIdentifiers: []),
            UNNotificationCategory(identifier: Self.readyCategory, actions: [again], intentIdentifiers: []),
            UNNotificationCategory(identifier: Self.leftOnCategory, actions: [off], intentIdentifiers: []),
        ])
    }

    /// Replaces every scheduled-drink reminder with the current list.
    func reschedule(_ schedules: [ScheduledBrew]) {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            let old = requests.map(\.identifier).filter { $0.hasPrefix("schedule-") }
            center.removePendingNotificationRequests(withIdentifiers: old)
            Task { @MainActor in
                for schedule in schedules where schedule.enabled {
                    self.add(schedule)
                }
            }
        }
    }

    private func add(_ schedule: ScheduledBrew) {
        let content = UNMutableNotificationContent()
        content.title = L("schedule.notify.title", schedule.recipe.displayName)
        content.body = schedule.ownerName.isEmpty ? L("schedule.notify.body") : L("schedule.notify.bodyFor", schedule.ownerName)
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        content.categoryIdentifier = Self.brewCategory
        content.userInfo = ["schedule": schedule.id.uuidString]
        let days = schedule.weekdays.isEmpty ? [nil] : schedule.weekdays.map { Optional($0) }
        for day in days {
            var components = DateComponents()
            components.hour = schedule.hour
            components.minute = schedule.minute
            components.weekday = day
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: day != nil)
            let id = "schedule-\(schedule.id.uuidString)-\(day ?? 0)"
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        }
    }

    /// "Rinse the milk carafe" a few minutes after a milk drink, unless done.
    func remindCarafe(after seconds: TimeInterval = 600) {
        let content = UNMutableNotificationContent()
        content.title = L("carafe.notify.title")
        content.body = L("carafe.notify.body")
        content.sound = .default
        content.categoryIdentifier = Self.carafeCategory
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: Self.carafeID, content: content, trigger: trigger))
    }

    func cancelCarafeReminder() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.carafeID])
    }

    /// One reminder per predicted care job, at 9:00 on its estimated day.
    func scheduleCare(_ forecast: CareForecast, enabled: Bool) {
        let center = UNUserNotificationCenter.current()
        let ids = CareTask.allCases.map { "care-\($0.rawValue)" }
        center.removePendingNotificationRequests(withIdentifiers: ids)
        guard enabled else { return }
        for item in forecast.items where item.daysLeft > 0 {
            var components = Calendar.current.dateComponents([.year, .month, .day], from: item.due)
            components.hour = 9
            let content = UNMutableNotificationContent()
            content.title = L("forecast.notify.title", item.task.title)
            content.body = L("forecast.notify.body")
            content.sound = .default
            center.add(UNNotificationRequest(identifier: "care-\(item.task.rawValue)", content: content,
                                             trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)))
        }
    }

    /// Each stage of a descaling run ends with a sound, even when locked.
    func scheduleDescaleStage(_ title: String, at date: Date) {
        let content = UNMutableNotificationContent()
        content.title = L("descale.notify.title")
        content.body = title
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        let seconds = max(1, date.timeIntervalSinceNow)
        UNUserNotificationCenter.current().add(UNNotificationRequest(
            identifier: "descale-stage", content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)))
    }

    func cancelDescaleStage() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["descale-stage"])
    }

    /// Sunday 20:00: a short weekly summary (refreshed every time the app opens).
    func scheduleWeeklySummary(_ text: String?, enabled: Bool) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["weekly-summary"])
        guard enabled, let text else { return }
        var components = DateComponents()
        components.weekday = 1
        components.hour = 20
        let content = UNMutableNotificationContent()
        content.title = L("summary.notify.title")
        content.body = text
        center.add(UNNotificationRequest(identifier: "weekly-summary", content: content,
                                         trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)))
    }
}

// MARK: - Version 3: milk, machine left on, warranty

extension NotificationManager {
    /// Ten minutes after a milk drink: the milk back in the fridge.
    func remindMilkToFridge() {
        let content = UNMutableNotificationContent()
        content.title = L("milkFridge.title")
        content.body = L("milkFridge.body")
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(
            identifier: "milk-fridge", content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 600, repeats: false)))
    }

    /// The morning the opened milk reaches its last day.
    func scheduleMilkExpiry(openedAt: Date?, shelfDays: Int) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["milk-expiry"])
        guard let openedAt, let day = Calendar.current.date(byAdding: .day, value: shelfDays, to: openedAt), day > Date() else { return }
        var components = Calendar.current.dateComponents([.year, .month, .day], from: day)
        components.hour = 8
        let content = UNMutableNotificationContent()
        content.title = L("milk.expiry.title")
        content.body = L("milk.lastDay")
        center.add(UNNotificationRequest(identifier: "milk-expiry", content: content,
                                         trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)))
    }

    /// The machine may still be on an hour after the last drink.
    func remindLeftOn(after seconds: TimeInterval) {
        let content = UNMutableNotificationContent()
        content.title = L("leftOn.title")
        content.body = L("leftOn.body")
        content.sound = .default
        content.categoryIdentifier = Self.leftOnCategory
        UNUserNotificationCenter.current().add(UNNotificationRequest(
            identifier: "left-on", content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)))
    }

    func cancelLeftOn() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["left-on"])
    }

    /// A countdown that ends with a sound even when the phone is locked.
    func scheduleTimer(id: String, title: String, body: String, seconds: Int) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        UNUserNotificationCenter.current().add(UNNotificationRequest(
            identifier: "timer-\(id)", content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(max(1, seconds)), repeats: false)))
    }

    func cancelTimer(id: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["timer-\(id)"])
    }

    /// Thirty days before the warranty ends.
    func scheduleWarranty(_ machine: MachineRecord) {
        let id = "warranty-\(machine.id.uuidString)"
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [id])
        guard let date = WarrantyReminder.date(for: machine), date > Date() else { return }
        let content = UNMutableNotificationContent()
        content.title = L("warranty.notify.title", machine.name)
        content.body = L("warranty.notify.body")
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        center.add(UNNotificationRequest(identifier: id, content: content,
                                         trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)))
    }
}

/// Opens the app from a reminder and acts on its buttons.
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationRouter()

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let action = response.actionIdentifier
        let info = response.notification.request.content.userInfo
        if action == NotificationManager.carafeAction {
            await MainActor.run { AppModel.shared.markCarafeCleaned() }
            return
        }
        if action == NotificationManager.turnOffAction {
            await MainActor.run {
                let model = AppModel.shared
                model.start()
                Task {
                    try? await IntentSupport.waitForConnection(model)
                    await model.powerOff()
                }
            }
            return
        }
        if action == NotificationManager.againAction, let raw = info["again"] as? String {
            await MainActor.run {
                let model = AppModel.shared
                let recipe = model.lastRecipe ?? model.usualRecipe
                if recipe.id.uuidString == raw || model.lastRecipe != nil { model.pendingScheduledRecipe = recipe }
            }
            return
        }
        guard let raw = info["schedule"] as? String,
              let id = UUID(uuidString: raw) else { return }
        let brewNow = response.actionIdentifier == NotificationManager.brewAction
        await MainActor.run { AppModel.shared.openScheduled(id, brewNow: brewNow) }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
