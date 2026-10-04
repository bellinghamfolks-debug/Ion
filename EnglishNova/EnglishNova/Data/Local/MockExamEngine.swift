import Foundation

/// A full, timed IELTS-style section built from the offline IELTS 6.0
/// material: every module of the section, 40 questions, one timer, and no
/// feedback until the end, like the real test.
struct MockExamSection: Hashable {
    let section: IELTSSection
    let modules: [IELTSObjectiveModule]
    let standardMinutes: Int

    var questions: [ComprehensionQuestion] { modules.flatMap(\.questions) }

    /// Minutes allowed, with optional 25% extra time (a common access
    /// arrangement for learners with disabilities).
    func minutes(extraTime: Bool) -> Int {
        extraTime ? Int((Double(standardMinutes) * 1.25).rounded(.up)) : standardMinutes
    }

    static func ielts(_ section: IELTSSection) -> MockExamSection {
        MockExamSection(
            section: section,
            modules: IELTSObjectiveLibrary.modules(for: section),
            standardMinutes: section == .listening ? 30 : 60
        )
    }
}

struct MockExamModuleResult: Hashable, Identifiable {
    let moduleID: String
    let titleAr: String
    let correct: Int
    let total: Int
    var id: String { moduleID }
}

struct MockExamResult: Hashable {
    let section: IELTSSection
    let correct: Int
    let total: Int
    let answered: Int
    let band: Double
    let modules: [MockExamModuleResult]
    let minutesUsed: Int

    var score: Double { total > 0 ? Double(correct) / Double(total) : 0 }

    /// Practice-session ID shared with the manual mock recorder, so one mock
    /// per section per day counts toward readiness and a retake replaces it.
    func sessionID(day: Date) -> String {
        let key = Int(day.startOfDay.timeIntervalSince1970)
        return "ielts-full-\(section == .listening ? "listening" : "reading")-\(key)"
    }
}

enum MockExamEngine {
    static func grade(_ exam: MockExamSection, answers: [String: String], minutesUsed: Int) -> MockExamResult {
        let modules = exam.modules.map { module in
            MockExamModuleResult(
                moduleID: module.id,
                titleAr: module.titleAr,
                correct: module.questions.filter { answers[$0.id] == $0.answer }.count,
                total: module.questions.count
            )
        }
        let correct = modules.reduce(0) { $0 + $1.correct }
        let total = modules.reduce(0) { $0 + $1.total }
        // Bands are defined on 40 questions; scale if the bank differs.
        let scaled = total == 40 || total == 0 ? correct : Int((Double(correct) * 40 / Double(total)).rounded())
        return MockExamResult(
            section: exam.section,
            correct: correct,
            total: total,
            answered: exam.questions.filter { !(answers[$0.id] ?? "").isEmpty }.count,
            band: IELTSBandSixEngine.objectiveBand(correct: scaled, section: exam.section),
            modules: modules,
            minutesUsed: max(1, minutesUsed)
        )
    }

    /// Minutes-left marks at which VoiceOver hears a time announcement.
    static let announcementMarks: Set<Int> = [10, 5, 1]
}
