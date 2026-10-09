import Foundation
#if canImport(ActivityKit)
import ActivityKit
#endif

/// Shared between the app and its widget extension: the Live Activity's
/// data, the snapshot the widgets read, and the coffeeaccess:// links.
enum SharedCoffee {
    static let appGroup = "group.com.coffeeaccess.app"
    static let snapshotKey = "widget.snapshot.v1"
    static let widgetKind = "CoffeeHomeWidget"
    static let statusWidgetKind = "CoffeeStatusWidget"
}

/// What the widgets show, written by the app whenever it changes.
struct WidgetSnapshot: Codable, Equatable {
    var usualName: String
    var usualSummary: String
    var usualLink: String
    var machineStatus: String
    var machineReady: Bool
    var caffeineToday: Int
    var caffeineLimit: Int
    var isArabic: Bool
    var updatedAt: Date

    static func load() -> WidgetSnapshot? {
        guard let data = UserDefaults(suiteName: SharedCoffee.appGroup)?.data(forKey: SharedCoffee.snapshotKey) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    /// Returns true when the stored value changed.
    @discardableResult
    func store() -> Bool {
        guard let defaults = UserDefaults(suiteName: SharedCoffee.appGroup) else { return false }
        var comparable = self
        if var old = Self.load() {
            old.updatedAt = comparable.updatedAt
            if old == comparable { return false }
        }
        comparable.updatedAt = Date()
        guard let data = try? JSONEncoder().encode(comparable) else { return false }
        defaults.set(data, forKey: SharedCoffee.snapshotKey)
        return true
    }
}

/// coffeeaccess://usual, coffeeaccess://brew/<beverage>, coffeeaccess://recipe?d=…
enum CoffeeLink {
    static let scheme = "coffeeaccess"
    static var usual: URL { URL(string: "\(scheme)://usual")! }
    static var stop: URL { URL(string: "\(scheme)://stop")! }
    static var home: URL { URL(string: "\(scheme)://home")! }
}

#if canImport(ActivityKit)
@available(iOS 16.2, *)
struct BrewActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var phase: String
        var percent: Int
        var finished: Bool
        var failed: Bool
    }

    var drinkName: String
    var isArabic: Bool
}
#endif
