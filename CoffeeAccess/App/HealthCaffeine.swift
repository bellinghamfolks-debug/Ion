import EventKit
import Foundation
import HealthKit

/// Writes the estimated caffeine of each finished drink to the Health app,
/// only when the person turned it on and allowed it.
@MainActor
final class HealthCaffeine {
    static let shared = HealthCaffeine()
    private let store = HKHealthStore()
    private let type = HKQuantityType(.dietaryCaffeine)

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// Asks for permission to write caffeine; returns false when refused or
    /// when this copy of the app was signed without Health access.
    func requestAccess() async -> Bool {
        guard isAvailable else { return false }
        do {
            try await store.requestAuthorization(toShare: [type], read: [])
            return store.authorizationStatus(for: type) == .sharingAuthorized
        } catch {
            return false
        }
    }

    func record(_ recipe: Recipe, enabled: Bool, at date: Date = Date()) {
        guard enabled, isAvailable, store.authorizationStatus(for: type) == .sharingAuthorized else { return }
        let mg = CaffeineEstimator.milligrams(for: recipe)
        guard mg > 0 else { return }
        let sample = HKQuantitySample(type: type, quantity: HKQuantity(unit: .gramUnit(with: .milli), doubleValue: Double(mg)),
                                      start: date, end: date, metadata: [HKMetadataKeyFoodType: recipe.displayName])
        store.save(sample) { _, _ in }
    }
}


/// Adds the shopping list to the Reminders app, in a list of its own.
enum RemindersWriter {
    static func add(_ titles: [String], listTitle: String) async -> Int {
        let store = EKEventStore()
        let granted = (try? await store.requestFullAccessToReminders()) ?? false
        guard granted else { return 0 }
        let calendar = store.calendars(for: .reminder).first { $0.title == listTitle } ?? {
            let created = EKCalendar(for: .reminder, eventStore: store)
            created.title = listTitle
            created.source = store.defaultCalendarForNewReminders()?.source ?? store.sources.first { $0.sourceType == .local }
            try? store.saveCalendar(created, commit: true)
            return created
        }()
        var added = 0
        for title in titles {
            let reminder = EKReminder(eventStore: store)
            reminder.title = title
            reminder.calendar = calendar
            if (try? store.save(reminder, commit: false)) != nil { added += 1 }
        }
        try? store.commit()
        return added
    }
}
