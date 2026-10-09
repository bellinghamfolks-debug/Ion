import Foundation

/// Which alarms come up most, for the alarm history and the service report.
enum AlarmStats {
    struct Count: Identifiable, Equatable {
        var alarm: MachineAlarm
        var count: Int
        var last: Date
        var id: MachineAlarm { alarm }
    }

    static func counts(_ events: [AlarmEvent], since: Date? = nil) -> [Count] {
        let relevant = events.filter { since == nil || $0.date >= since! }
        let grouped = Dictionary(grouping: relevant, by: \.alarm)
        return grouped.map { alarm, events in
            Count(alarm: alarm, count: events.count, last: events.map(\.date).max() ?? Date())
        }
        .sorted { $0.count == $1.count ? $0.alarm.rawValue < $1.alarm.rawValue : $0.count > $1.count }
    }
}

/// A plain-text report for a service centre: the machine, its warranty,
/// counters, care history and recent alarms.
enum ServiceReport {
    static func text(machine: MachineRecord?, counters: MachineCounters, log: [MaintenanceEntry], alarms: [AlarmEvent],
                     appVersion: String, now: Date = Date()) -> String {
        let date = Date.FormatStyle(date: .abbreviated, time: .omitted).locale(AppLanguage.current.locale)
        var lines = [L("report.title"), ""]
        if let machine {
            lines.append(L("report.machine", machine.name, machine.model))
            if !machine.serial.isEmpty { lines.append(L("report.serial", machine.serial)) }
            if let bought = machine.purchaseDate { lines.append(L("report.bought", bought.formatted(date))) }
            if let ends = machine.warrantyEnds { lines.append(L("report.warranty", ends.formatted(date))) }
        }
        if !counters.isEmpty {
            lines.append("")
            lines.append(L("report.counters"))
            lines += counters.reportLines
        }
        lines.append("")
        lines.append(L("report.care"))
        for task in CareTask.allCases {
            let last = log.first { $0.task == task }?.date
            lines.append("• \(task.title): \(last.map { $0.formatted(date) } ?? L("report.never"))")
        }
        let monthAgo = Calendar.current.date(byAdding: .day, value: -30, to: now) ?? now
        let counts = AlarmStats.counts(alarms, since: monthAgo)
        lines.append("")
        lines.append(L("report.alarms"))
        if counts.isEmpty { lines.append(L("report.none")) }
        for count in counts { lines.append("• \(count.alarm.title): \(count.count)") }
        lines.append("")
        lines.append(L("report.footer", appVersion))
        return lines.joined(separator: "\n")
    }
}

/// Before moving the machine or leaving it for a long time.
enum TravelChecklist {
    static let count = 8
    static var items: [String] { (1...count).map { L("travel.item.\($0)") } }
}

/// Opened milk keeps a few days in the fridge.
enum MilkFreshness {
    static func daysLeft(openedAt: Date?, shelfDays: Int, now: Date = Date(), calendar: Calendar = .current) -> Int? {
        guard let openedAt else { return nil }
        let used = calendar.dateComponents([.day], from: calendar.startOfDay(for: openedAt), to: calendar.startOfDay(for: now)).day ?? 0
        return shelfDays - used
    }

    static func warning(openedAt: Date?, shelfDays: Int, now: Date = Date()) -> String? {
        guard let left = daysLeft(openedAt: openedAt, shelfDays: shelfDays, now: now) else { return nil }
        if left < 0 { return L("milk.expired") }
        if left == 0 { return L("milk.lastDay") }
        return nil
    }
}

/// Water standing in the tank for days tastes flat; fresh water is better.
enum TankWater {
    static let freshDays = 2

    static func isStale(filledAt: Date?, now: Date = Date()) -> Bool {
        guard let filledAt else { return false }
        return now.timeIntervalSince(filledAt) > Double(freshDays) * 86_400
    }

    static func days(since filledAt: Date?, now: Date = Date()) -> Int {
        guard let filledAt else { return 0 }
        return Int(now.timeIntervalSince(filledAt) / 86_400)
    }
}

/// A rough monthly energy estimate: heating up, each drink, and standby.
enum EnergyEstimate {
    static let perDrinkKWh = 0.025
    static let perDayInUseKWh = 0.05
    static let standbyKWhPerDay = 0.012

    static func month(history: [BrewRecord], now: Date = Date(), calendar: Calendar = .current) -> Double {
        let start = calendar.date(byAdding: .day, value: -30, to: now) ?? now
        let cups = history.filter { $0.completed && $0.date >= start }
        let days = Set(cups.map { calendar.startOfDay(for: $0.date) }).count
        return Double(cups.count) * perDrinkKWh + Double(days) * perDayInUseKWh + 30 * standbyKWhPerDay
    }
}

/// Bluetooth signal strength in words.
enum SignalStrength: String {
    case strong, fair, weak

    init(rssi: Int) {
        switch rssi {
        case (-65)...: self = .strong
        case (-80)..<(-65): self = .fair
        default: self = .weak
        }
    }

    var title: String { L("signal.strength.\(rawValue)") }
    var bars: Int { self == .strong ? 3 : (self == .fair ? 2 : 1) }
}

/// The four profile names in the app and on the machine, side by side.
/// Writing names to the machine is not documented, so the app explains how
/// to rename on the machine instead of sending an unverified command.
enum ProfileNameCheck {
    struct Row: Identifiable, Equatable {
        var id: Int
        var app: String
        var machine: String?
        var matches: Bool { machine.map { $0.caseInsensitiveCompare(app) == .orderedSame } ?? true }
    }

    static func rows(app: [UserProfile], machine: [Int: String]) -> [Row] {
        app.map { Row(id: $0.id, app: $0.name, machine: machine[$0.id]) }
    }
}

extension MachineCounters {
    /// What the machine counted, one line each, for the service report.
    var reportLines: [String] {
        var lines: [String] = []
        if let value = totalCoffee { lines.append("• " + L("report.counter.coffee", value)) }
        if let value = milkDrinks { lines.append("• " + L("report.counter.milk", value)) }
        if let value = descaleCount { lines.append("• " + L("report.counter.descale", value)) }
        if let value = filterReplacements { lines.append("• " + L("report.counter.filter", value)) }
        if let value = waterLitres { lines.append("• " + L("report.counter.water", Int(value.rounded()))) }
        return lines
    }
}

enum WarrantyReminder {
    /// 30 days before the warranty ends, at 10:00.
    static func date(for machine: MachineRecord, calendar: Calendar = .current) -> Date? {
        guard let ends = machine.warrantyEnds, let before = calendar.date(byAdding: .day, value: -30, to: ends) else { return nil }
        return calendar.date(bySettingHour: 10, minute: 0, second: 0, of: before)
    }
}
