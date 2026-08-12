import Foundation

struct LessonExerciseEvidence: Hashable {
    let type: ExerciseType
    let wasCorrect: Bool
    let choiceCount: Int
}

struct LessonAssessment: Hashable {
    let rawAccuracy: Double
    let masteryScore: Double
    let receptiveScore: Double?
    let controlledScore: Double?
    let productiveScore: Double?
    let gradedCount: Int
    let productiveCount: Int
    let passThreshold: Double
    let productiveFloor: Double?
    let passed: Bool

    var percent: Int { Int((masteryScore * 100).rounded()) }
}

enum LessonAssessmentEngine {
    private enum EvidenceGroup { case receptive, controlled, productive }

    static func evaluate(level: CEFRLevel, evidence: [LessonExerciseEvidence]) -> LessonAssessment {
        let graded = evidence.filter { $0.type != .explanation && $0.type != .flashcard }
        guard !graded.isEmpty else {
            return LessonAssessment(rawAccuracy: 1, masteryScore: 1, receptiveScore: nil,
                                    controlledScore: nil, productiveScore: nil, gradedCount: 0,
                                    productiveCount: 0, passThreshold: threshold(for: level),
                                    productiveFloor: productiveFloor(for: level), passed: true)
        }

        let raw = Double(graded.filter(\.wasCorrect).count) / Double(graded.count)
        let receptive = score(group: .receptive, evidence: graded)
        let controlled = score(group: .controlled, evidence: graded)
        let productive = score(group: .productive, evidence: graded)
        let productiveCount = graded.filter { group(for: $0.type) == .productive }.count

        let weights = groupWeights(for: level)
        let candidates: [(Double?, Double)] = [
            (receptive, weights.receptive),
            (controlled, weights.controlled),
            (productive, weights.productive)
        ]
        let active = candidates.filter { $0.0 != nil }
        let totalWeight = active.reduce(0) { $0 + $1.1 }
        var mastery = totalWeight > 0
            ? active.reduce(0) { $0 + ($1.0 ?? 0) * $1.1 } / totalWeight
            : raw

        let floor = productiveFloor(for: level)
        if let floor, productive == nil {
            mastery = min(mastery, 0.59)
        }

        let passThreshold = threshold(for: level)
        let productiveRequirementMet = floor.map { (productive ?? 0) >= $0 } ?? true
        let passed = mastery >= passThreshold && productiveRequirementMet

        return LessonAssessment(
            rawAccuracy: raw,
            masteryScore: min(1, max(0, mastery)),
            receptiveScore: receptive,
            controlledScore: controlled,
            productiveScore: productive,
            gradedCount: graded.count,
            productiveCount: productiveCount,
            passThreshold: passThreshold,
            productiveFloor: floor,
            passed: passed
        )
    }

    static func threshold(for level: CEFRLevel) -> Double {
        switch level {
        case .a0: return 0.65
        case .a1: return 0.68
        case .a2: return 0.72
        case .b1: return 0.75
        case .b2: return 0.78
        case .c1: return 0.82
        }
    }

    private static func productiveFloor(for level: CEFRLevel) -> Double? {
        switch level {
        case .a0, .a1: return nil
        case .a2: return 0.45
        case .b1: return 0.55
        case .b2: return 0.62
        case .c1: return 0.70
        }
    }

    private static func groupWeights(for level: CEFRLevel) -> (receptive: Double, controlled: Double, productive: Double) {
        switch level {
        case .a0, .a1: return (0.45, 0.35, 0.20)
        case .a2: return (0.40, 0.30, 0.30)
        case .b1: return (0.35, 0.30, 0.35)
        case .b2: return (0.30, 0.25, 0.45)
        case .c1: return (0.25, 0.20, 0.55)
        }
    }

    private static func score(group target: EvidenceGroup, evidence: [LessonExerciseEvidence]) -> Double? {
        let items = evidence.filter { group(for: $0.type) == target }
        guard !items.isEmpty else { return nil }

        if target == .receptive {
            let observed = Double(items.filter(\.wasCorrect).count) / Double(items.count)
            let baseline = items.reduce(0.0) { partial, item in
                let count = max(2, item.choiceCount)
                return partial + 1.0 / Double(count)
            } / Double(items.count)
            guard baseline < 1 else { return observed }
            return min(1, max(0, (observed - baseline) / (1 - baseline)))
        }

        let weighted: [(LessonExerciseEvidence, Double)] = items.map { item in
            let weight: Double
            switch item.type {
            case .fillBlank: weight = 1.15
            case .arrangeWords: weight = 1.0
            case .translation: weight = 1.65
            case .speak: weight = 1.85
            default: weight = 1
            }
            return (item, weight)
        }
        let total = weighted.reduce(0) { $0 + $1.1 }
        let correct = weighted.reduce(0) { $0 + ($1.0.wasCorrect ? $1.1 : 0) }
        return total > 0 ? correct / total : nil
    }

    private static func group(for type: ExerciseType) -> EvidenceGroup? {
        switch type {
        case .multipleChoice, .listenAndChoose: return .receptive
        case .fillBlank, .arrangeWords: return .controlled
        case .translation, .speak: return .productive
        case .explanation, .flashcard: return nil
        }
    }
}
