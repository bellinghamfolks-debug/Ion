import Foundation

struct AdaptivePlacementEngine {
    private(set) var responses: [PlacementResponse] = []
    private(set) var ability: Double = 1.0
    private let questions: [PlacementQuestion]
    private var usedQuestionIDs: Set<String> = []
    private var skillCounts: [LanguageSkill: Int] = [:]

    init(questions: [PlacementQuestion], startingLevel: CEFRLevel = .a1) {
        self.questions = questions
        self.ability = Double(Self.index(of: startingLevel))
    }

    var minimumQuestions: Int { 12 }
    var maximumQuestions: Int { 24 }

    mutating func nextQuestion() -> PlacementQuestion? {
        guard responses.count < maximumQuestions else { return nil }
        let available = questions.filter { !usedQuestionIDs.contains($0.id) }
        guard !available.isEmpty else { return nil }

        let leastPracticed = LanguageSkill.allCases.min {
            skillCounts[$0, default: 0] < skillCounts[$1, default: 0]
        }
        let pool = available.filter { question in
            guard let leastPracticed else { return true }
            let current = skillCounts[question.skill, default: 0]
            return current <= skillCounts[leastPracticed, default: 0] + 1
        }
        let source = pool.isEmpty ? available : pool

        let selected = source.min { left, right in
            let leftDistance = abs(Double(Self.index(of: left.level)) - ability)
            let rightDistance = abs(Double(Self.index(of: right.level)) - ability)
            if leftDistance == rightDistance {
                return left.discrimination > right.discrimination
            }
            return leftDistance < rightDistance
        }
        if let selected { usedQuestionIDs.insert(selected.id) }
        return selected
    }

    mutating func submit(question: PlacementQuestion, selectedAnswer: String, at date: Date = .now) {
        let correct = selectedAnswer == question.answer
        let difficulty = Double(Self.index(of: question.level))
        let probability = 1 / (1 + exp(-1.35 * (ability - difficulty)))
        let observed = correct ? 1.0 : 0.0
        let step = max(0.20, 0.62 - Double(responses.count) * 0.016)
        ability = min(5, max(0, ability + step * question.discrimination * (observed - probability)))
        skillCounts[question.skill, default: 0] += 1
        responses.append(PlacementResponse(
            questionID: question.id,
            level: question.level,
            skill: question.skill,
            selectedAnswer: selectedAnswer,
            wasCorrect: correct,
            answeredAt: date
        ))
    }

    var shouldFinish: Bool {
        guard responses.count >= minimumQuestions else { return false }
        if responses.count >= maximumQuestions { return true }
        let recent = responses.suffix(6)
        let levelSpan = Set(recent.map { Self.index(of: $0.level) }).count
        let skillCoverage = Set(responses.map(\.skill)).count
        return responses.count >= 16 && levelSpan <= 2 && skillCoverage == LanguageSkill.allCases.count
    }

    func result(at date: Date = .now) -> PlacementResult {
        let recommended = Self.level(forAbility: ability)
        let grouped = Dictionary(grouping: responses, by: \.skill)
        let skills = LanguageSkill.allCases.map { skill in
            let answers = grouped[skill] ?? []
            let correct = answers.filter(\.wasCorrect).count
            return PlacementSkillResult(
                skill: skill,
                score: answers.isEmpty ? 0 : Double(correct) / Double(answers.count),
                answered: answers.count
            )
        }
        let confidence = min(0.97, 0.42 + Double(responses.count) * 0.022 + Double(Set(responses.map(\.skill)).count) * 0.035)
        return PlacementResult(
            recommendedLevel: recommended,
            ability: ability,
            confidence: confidence,
            responses: responses,
            skills: skills,
            completedAt: date
        )
    }

    static func index(of level: CEFRLevel) -> Int {
        CEFRLevel.allCases.firstIndex(of: level) ?? 0
    }

    static func level(forAbility ability: Double) -> CEFRLevel {
        let rounded = Int(ability.rounded())
        return CEFRLevel.allCases[min(CEFRLevel.allCases.count - 1, max(0, rounded))]
    }
}
