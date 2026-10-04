import Foundation

/// The six skills shown on the dashboard.
enum DashboardSkill: String, CaseIterable, Identifiable, Hashable {
    case vocabulary, grammar, reading, listening, speaking, writing

    var id: String { rawValue }

    var title: String {
        switch self {
        case .vocabulary: return LE("المفردات", "Vocabulary")
        case .grammar: return LE("القواعد", "Grammar")
        case .reading: return LE("القراءة", "Reading")
        case .listening: return LE("الاستماع", "Listening")
        case .speaking: return LE("التحدث", "Speaking")
        case .writing: return LE("الكتابة", "Writing")
        }
    }

    var systemImage: String {
        switch self {
        case .vocabulary: return "character.book.closed.fill"
        case .grammar: return "function"
        case .reading: return "book.pages.fill"
        case .listening: return "headphones"
        case .speaking: return "waveform.and.mic"
        case .writing: return "pencil.and.scribble"
        }
    }

    var languageSkill: LanguageSkill? {
        switch self {
        case .vocabulary: return .vocabulary
        case .grammar: return .grammar
        case .reading: return .reading
        case .listening: return .listening
        case .speaking: return .practicalCommunication
        case .writing: return nil
        }
    }

    var domain: AdvancedSkillDomain {
        switch self {
        case .vocabulary: return .vocabulary
        case .grammar: return .grammar
        case .reading: return .reading
        case .listening: return .listening
        case .speaking: return .speaking
        case .writing: return .writing
        }
    }
}

struct SkillScore: Identifiable, Hashable {
    let skill: DashboardSkill
    /// 0...1, nil when there is not enough evidence yet.
    let value: Double?
    let evidence: Int
    var id: DashboardSkill { skill }
}

struct CEFREstimate: Hashable {
    let level: CEFRLevel
    /// 0...1 progress through `level` toward the next one.
    let progressInLevel: Double
    /// low / medium / high depending on how much evidence there is.
    let confidence: Confidence

    enum Confidence: String, Hashable { case low, medium, high }
}

/// Turns local progress into six skill scores and an approximate CEFR level.
/// Pure and deterministic. It is an estimate for motivation and planning, not
/// a certified result; the UI says so.
enum SkillsDashboardEngine {
    static let minimumEvidence = 5

    static func scores(progress: UserProgressSnapshot) -> [SkillScore] {
        DashboardSkill.allCases.map { skill in
            var weighted = 0.0
            var weight = 0.0
            var evidence = 0

            if let languageSkill = skill.languageSkill, let metric = progress.skills[languageSkill], metric.attempts > 0 {
                weighted += metric.accuracy * Double(metric.attempts)
                weight += Double(metric.attempts)
                evidence += metric.attempts
            }
            // Each practice session counts like four answers.
            let sessions = progress.practiceSessions.filter { $0.domain == skill.domain }.prefix(30)
            for session in sessions {
                weighted += min(1, max(0, session.score)) * 4
                weight += 4
                evidence += 1
            }
            let value = (weight > 0 && evidence >= minimumEvidence) ? weighted / weight : nil
            return SkillScore(skill: skill, value: value, evidence: evidence)
        }
    }

    static func estimate(catalog: CourseCatalog?, progress: UserProgressSnapshot, selectedLevel: CEFRLevel) -> CEFREstimate {
        let levels = CEFRLevel.allCases
        var reached: CEFRLevel?
        var progressInLevel = 0.0

        // Coursework: a level counts as reached when 80% of its lessons are
        // passed with an average best score of at least 70%.
        for course in catalog?.levels.sorted(by: { order($0.level) < order($1.level) }) ?? [] {
            let lessons = course.units.flatMap(\.lessons)
            guard !lessons.isEmpty else { continue }
            let passed = lessons.compactMap { progress.lessons[$0.id] }.filter { $0.completedAt != nil }
            let share = Double(passed.count) / Double(lessons.count)
            let average = passed.isEmpty ? 0 : passed.map(\.bestScore).reduce(0, +) / Double(passed.count)
            if share >= 0.8 && average >= 0.7 {
                reached = course.level
            } else {
                progressInLevel = min(0.99, share)
                break
            }
        }

        var level = reached.map { next(after: $0) } ?? levels.first ?? .a0
        if reached == .c1 { level = .c1; progressInLevel = 1 }

        // A recent placement test is stronger evidence than early coursework.
        if let placement = progress.lastPlacementResult,
           placement.confidence >= 0.6,
           order(placement.recommendedLevel) > order(level),
           Date().timeIntervalSince(placement.completedAt) < 120 * 86_400 {
            level = placement.recommendedLevel
            progressInLevel = 0
        }

        let evidence = progress.lessons.values.filter { $0.completedAt != nil }.count
            + progress.practiceSessions.count
            + (progress.lastPlacementResult == nil ? 0 : 10)
        let confidence: CEFREstimate.Confidence = evidence >= 40 ? .high : (evidence >= 12 ? .medium : .low)
        return CEFREstimate(level: level, progressInLevel: max(0, min(1, progressInLevel)), confidence: confidence)
    }

    /// The weakest skill with evidence, to suggest what to practise next.
    static func focus(_ scores: [SkillScore]) -> DashboardSkill? {
        let known = scores.filter { $0.value != nil }
        if let weakest = known.min(by: { ($0.value ?? 1) < ($1.value ?? 1) }), (weakest.value ?? 1) < 0.8 {
            return weakest.skill
        }
        // Otherwise the skill with the least evidence.
        return scores.min(by: { $0.evidence < $1.evidence })?.skill
    }

    private static func order(_ level: CEFRLevel) -> Int {
        CEFRLevel.allCases.firstIndex(of: level) ?? 0
    }

    private static func next(after level: CEFRLevel) -> CEFRLevel {
        let all = CEFRLevel.allCases
        guard let index = all.firstIndex(of: level), index + 1 < all.count else { return level }
        return all[index + 1]
    }
}
