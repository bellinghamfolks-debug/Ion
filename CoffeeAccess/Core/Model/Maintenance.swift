import Foundation

enum MaintenanceGuideID: String, CaseIterable, Identifiable {
    case fillWater, fillBeans, emptyContainers, milkCarafe, coldCarafe, brewingUnit, waterFilter, waterHardness, descaling

    var id: String { rawValue }

    /// Number of steps; their text lives in the strings table as
    /// "guide.<id>.step.<n>" (1-based).
    var stepCount: Int {
        switch self {
        case .fillWater: return 4
        case .fillBeans: return 4
        case .emptyContainers: return 5
        case .milkCarafe: return 6
        case .coldCarafe: return 5
        case .brewingUnit: return 7
        case .waterFilter: return 6
        case .waterHardness: return 5
        case .descaling: return 9
        }
    }

    var minutes: Int {
        switch self {
        case .fillWater, .fillBeans: return 1
        case .emptyContainers: return 2
        case .milkCarafe: return 5
        case .coldCarafe: return 5
        case .brewingUnit: return 10
        case .waterFilter: return 5
        case .waterHardness: return 2
        case .descaling: return 45
        }
    }

    var symbol: String {
        switch self {
        case .fillWater: return "drop.fill"
        case .fillBeans: return "leaf.fill"
        case .emptyContainers: return "trash.fill"
        case .milkCarafe: return "cup.and.saucer.fill"
        case .coldCarafe: return "snowflake"
        case .waterHardness: return "testtube.2"
        case .brewingUnit: return "gearshape.2.fill"
        case .waterFilter: return "line.3.horizontal.decrease.circle.fill"
        case .descaling: return "sparkles"
        }
    }

    var title: String { L("guide.\(rawValue).title") }
    var intro: String { L("guide.\(rawValue).intro") }
    var steps: [String] { (1...stepCount).map { L("guide.\(rawValue).step.\($0)") } }
}
