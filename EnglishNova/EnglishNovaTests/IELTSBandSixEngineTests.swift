import XCTest
@testable import EnglishNova

final class IELTSBandSixEngineTests: XCTestCase {
    func testEveryPhaseProducesExactlyThreeMeasuredHours() {
        for level in CEFRLevel.allCases {
            let blocks = IELTSBandSixEngine.dailyBlocks(
                level: level,
                progress: UserProgressSnapshot(),
                dueCardCount: 12,
                date: Date(timeIntervalSince1970: 1_788_739_200)
            )
            XCTAssertEqual(blocks.reduce(0) { $0 + $1.minutes }, 180, "Failed for \(level.rawValue)")
            XCTAssertTrue(blocks.allSatisfy { $0.minutes >= 10 })
            XCTAssertTrue(blocks.contains { $0.area == .listening })
            XCTAssertTrue(blocks.contains { $0.area == .reading })
            XCTAssertTrue(blocks.contains { $0.area == .writing })
            XCTAssertTrue(blocks.contains { $0.area == .speaking })
        }
    }

    func testIELTSPlanCannotBeShortenedBelow180Minutes() throws {
        let catalog = try BundledContentLoader().loadCatalog()
        let plan = LearningPlanner.makePlan(
            catalog: catalog,
            progress: UserProgressSnapshot(),
            dueCards: [],
            level: .a0,
            targetMinutes: 5,
            reducePressure: true,
            studyMode: .calm,
            pathway: .academicIELTS
        )

        XCTAssertEqual(plan.targetMinutes, 180)
        XCTAssertEqual(plan.items.reduce(0) { $0 + $1.estimatedMinutes }, 180)
        XCTAssertTrue(plan.items.allSatisfy { $0.referenceID?.hasPrefix("ielts:") == true })
    }

    func testConfiguredIELTSTimeAboveMinimumIsPreserved() throws {
        let catalog = try BundledContentLoader().loadCatalog()
        let plan = LearningPlanner.makePlan(
            catalog: catalog,
            progress: UserProgressSnapshot(),
            dueCards: [],
            level: .b1,
            targetMinutes: 210,
            reducePressure: false,
            pathway: .academicIELTS
        )
        XCTAssertEqual(plan.targetMinutes, 210)
        XCTAssertEqual(plan.items.reduce(0) { $0 + $1.estimatedMinutes }, 210)
    }

    func testPublishedBandSixObjectiveAnchors() {
        XCTAssertEqual(IELTSBandSixEngine.objectiveBand(correct: 23, section: .listening), 6.0)
        XCTAssertEqual(IELTSBandSixEngine.objectiveBand(correct: 30, section: .listening), 7.0)
        XCTAssertEqual(IELTSBandSixEngine.objectiveBand(correct: 23, section: .reading), 6.0)
        XCTAssertEqual(IELTSBandSixEngine.objectiveBand(correct: 30, section: .reading), 7.0)
        XCTAssertEqual(IELTSBandSixEngine.objectiveBand(correct: 100, section: .reading), 9.0)
        XCTAssertEqual(IELTSBandSixEngine.objectiveBand(correct: -5, section: .listening), 0)
    }

    func testOverallBandUsesIELTSHalfBandRounding() {
        XCTAssertEqual(IELTSBandSixEngine.officialOverallBand(sectionBands: [6.5, 6.5, 5.0, 7.0]), 6.5)
        XCTAssertEqual(IELTSBandSixEngine.officialOverallBand(sectionBands: [6.5, 6.5, 5.5, 6.0]), 6.0)
        XCTAssertNil(IELTSBandSixEngine.officialOverallBand(sectionBands: [6, 6, 6]))
    }

    func testProductiveBandRoundTripKeepsBandSixThreshold() {
        XCTAssertEqual(IELTSBandSixEngine.practicePerformance(forEstimatedBand: 6), 0.68, accuracy: 0.001)
        XCTAssertEqual(IELTSBandSixEngine.practicePerformance(forEstimatedBand: 5.5), 0.58, accuracy: 0.001)
        XCTAssertEqual(IELTSBandSixEngine.practicePerformance(forEstimatedBand: 9), 1, accuracy: 0.001)
    }

    func testObjectiveLibraryProvidesFortyUniqueQuestionsPerSection() {
        for (section, modules) in [
            (IELTSSection.reading, IELTSObjectiveLibrary.readingModules),
            (IELTSSection.listening, IELTSObjectiveLibrary.listeningModules)
        ] {
            XCTAssertEqual(modules.count, 4)
            XCTAssertEqual(modules.flatMap(\.questions).count, 40)
            XCTAssertEqual(Set(modules.flatMap(\.questions).map(\.id)).count, 40)
            XCTAssertTrue(modules.allSatisfy { $0.section == section })
            XCTAssertTrue(modules.allSatisfy { !$0.sourceText.isEmpty })
            XCTAssertTrue(modules.allSatisfy { $0.questions.allSatisfy { $0.choices.contains($0.answer) } })
        }
    }

    func testReadinessRefusesBandWhenEvidenceIsMissing() {
        let value = IELTSBandSixEngine.readiness(level: .b2, progress: UserProgressSnapshot())
        XCTAssertNil(value.overallBand)
        XCTAssertFalse(value.isReadyForBandSix)
        XCTAssertEqual(value.blockersAr.count, 4)
    }

    func testReadinessRequiresRecentEvidenceAcrossAllFourSections() {
        let now = Date(timeIntervalSince1970: 1_788_739_200)
        var sessions: [PracticeSessionRecord] = []
        for section in IELTSSection.allCases {
            for index in 0..<4 {
                sessions.append(PracticeSessionRecord(
                    id: "\(section.rawValue)-\(index)",
                    domain: section.practiceDomain,
                    sourceID: "ielts-test-\(section.rawValue)-\(index)",
                    titleAr: section.titleAr,
                    level: .b2,
                    score: section == .reading || section == .listening ? 0.65 : 0.72,
                    minutes: 30,
                    createdAt: now.addingTimeInterval(Double(-index * 2) * 86_400),
                    details: []
                ))
            }
        }
        let progress = UserProgressSnapshot(practiceSessions: sessions)
        let value = IELTSBandSixEngine.readiness(level: .b2, progress: progress, now: now)

        XCTAssertTrue(value.hasCompleteEvidence)
        XCTAssertNotNil(value.overallBand)
        XCTAssertTrue(value.sectionEstimates.allSatisfy { ($0.estimatedBand ?? 0) >= 5.5 })
        XCTAssertTrue(value.isReadyForBandSix)
    }

    func testWritingEvaluationIsConservativeAndChecksMinimumLength() {
        let task = IELTSBandSixEngine.writingTasks.first { $0.type == .academicTask1 }!
        let short = IELTSBandSixEngine.evaluateWriting(
            text: "Overall, car use fell while rail use increased.",
            task: task
        )
        XCTAssertLessThanOrEqual(short.estimatedBand, 5.0)
        XCTAssertTrue(short.improvementsAr.contains { $0.contains("كلمة") })
        XCTAssertEqual(IELTSBandSixEngine.writingTasks.count, 12)
        XCTAssertTrue(IELTSBandSixEngine.writingTasks
            .filter { $0.type == .academicTask1 }
            .allSatisfy { $0.accessibleSourceDescription?.isEmpty == false })
    }

    func testLegacyDailyPlanDecodesWithoutLoggedMinutes() throws {
        let json = """
        {"date":0,"targetMinutes":180,"items":[]}
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let plan = try decoder.decode(DailyLearningPlan.self, from: json)
        XCTAssertEqual(plan.loggedMinutes, 0)
        XCTAssertEqual(plan.remainingMinutes, 180)
    }
}
