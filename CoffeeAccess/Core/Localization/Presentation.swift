import Foundation

extension BeverageID {
    var name: String { L("drink.\(rawValue).name") }
    var summary: String { L("drink.\(rawValue).summary") }
}

extension BeverageCategory {
    var title: String { L("category.\(rawValue)") }
}

extension Recipe {
    var displayName: String { customName.isEmpty ? beverage.name : customName }

    /// One sentence describing every setting, read before brewing and by
    /// VoiceOver on favorites: "Cappuccino: 60 ml coffee, strong, …".
    var spokenSummary: String {
        var parts: [String] = []
        if let coffee = coffeeML { parts.append(L(spec.vessel == .pot ? "summary.pot" : "summary.coffee", coffee)) }
        if let water = waterML { parts.append(L("summary.water", water)) }
        if let milk = milkSeconds { parts.append(L("summary.milk", milk)) }
        if let aroma { parts.append(aroma.title) }
        if let temperature { parts.append(L("summary.temperature", spec.isTea ? temperature.teaTitle : temperature.title)) }
        if milkFirst { parts.append(L("summary.milkFirst")) }
        if extraShot { parts.append(L("summary.extraShot")) }
        if toGo { parts.append(L("summary.toGo")) }
        let details = parts.joined(separator: L("list.separator"))
        return details.isEmpty ? displayName : L("summary.format", displayName, details)
    }

    /// Short line for cards: "60 ml · Strong".
    var shortDetails: String {
        var parts: [String] = []
        if let coffee = coffeeML { parts.append(L("unit.ml", coffee)) }
        if let water = waterML, coffeeML == nil { parts.append(L("unit.ml", water)) }
        if let milk = milkSeconds, coffeeML == nil { parts.append(L("unit.seconds", milk)) }
        if let aroma { parts.append(aroma.title) }
        return parts.joined(separator: " · ")
    }
}

extension Aroma {
    var title: String {
        switch self {
        case .extraMild: return L("aroma.extraMild")
        case .mild: return L("aroma.mild")
        case .normal: return L("aroma.normal")
        case .strong: return L("aroma.strong")
        case .extraStrong: return L("aroma.extraStrong")
        }
    }
}

extension BrewTemperature {
    var title: String {
        switch self {
        case .low: return L("temperature.low")
        case .medium: return L("temperature.medium")
        case .high: return L("temperature.high")
        }
    }
}

extension MachineAlarm {
    var title: String { L("alarm.\(rawValue).title") }
    var advice: String { L("alarm.\(rawValue).advice") }
}

extension MachinePower {
    var title: String { L("power.\(rawValue)") }
}

extension MachineActivity {
    var title: String { L("activity.\(rawValue)") }

    var phaseAnnouncement: String? {
        switch self {
        case .grinding, .brewingCoffee, .dispensingMilk, .dispensingWater, .steaming: return title
        default: return nil
        }
    }
}

extension MilkAccessory {
    var title: String { L("accessory.\(rawValue)") }
}

extension ConnectionState {
    var title: String {
        switch self {
        case .disconnected: return L("connection.disconnected")
        case .searching: return L("connection.searching")
        case .connecting(let name): return L("connection.connecting", name)
        case .connected(let name): return L("connection.connected", name)
        case .failed(let reason): return L("connection.failed", reason)
        }
    }
}

extension MachineLinkKind {
    var title: String { L("link.\(rawValue).title") }
    var detail: String { L("link.\(rawValue).detail") }
}

extension MachineSnapshot {
    /// The headline for the status card and the Siri answer.
    var headline: String {
        if let alarm = blockingAlarms.first { return alarm.title }
        if power == .busy, activity != .idle { return activity.title }
        return power.title
    }

    var spokenStatus: String {
        var sentences = [headline]
        let others = alarms.filter { $0.title != headline }
        if !others.isEmpty { sentences.append(L("status.alsoAlarms", others.map(\.title).joined(separator: L("list.separator")))) }
        return sentences.joined(separator: L("sentence.separator"))
    }
}

extension BrewTemperature {
    /// Tea uses the same three levels, named by the water temperature.
    var teaTitle: String { L("teaTemperature.\(String(describing: self))") }
}

extension DrinkCollection {
    var title: String { L("collection.\(rawValue).title") }
    var summary: String { L("collection.\(rawValue).summary") }
}

extension BeanProfile.Roast {
    var title: String { L("roast.\(rawValue)") }
}

extension BeanProfile.Kind {
    var title: String { L("beanKind.\(rawValue)") }
}

extension BeanProfile {
    var summary: String {
        L("bean.summary", roast.title, kind.title, recommendedGrind, recommendedTemperature.title)
    }
}

extension MachineSettings.AutoOff {
    var title: String {
        switch self {
        case .fifteenMinutes: return L("autoOff.15")
        case .thirtyMinutes: return L("autoOff.30")
        case .oneHour: return L("autoOff.60")
        case .twoHours: return L("autoOff.120")
        case .threeHours: return L("autoOff.180")
        }
    }
}

enum WaterHardness {
    static func title(_ level: Int) -> String { L("hardness.\(max(1, min(level, 4)))") }
}

enum WaterTemperatureLevel {
    static func title(_ level: Int) -> String { L("waterTemperature.\(max(0, min(level, 3)))") }
}
