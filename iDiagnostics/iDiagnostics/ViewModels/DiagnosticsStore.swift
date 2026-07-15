import Foundation
import Combine

/// Central state for the whole app (MVVM). Every test screen writes its
/// outcome here via `record(_:)`; the dashboard and report read from it.
@MainActor
final class DiagnosticsStore: ObservableObject {
    /// Results keyed by category, seeded as `.notRun`.
    @Published private(set) var results: [TestCategory: TestResult]

    init() {
        var seed: [TestCategory: TestResult] = [:]
        for category in TestCategory.allCases {
            seed[category] = TestResult(category: category)
        }
        results = seed
    }

    func result(for category: TestCategory) -> TestResult {
        results[category] ?? TestResult(category: category)
    }

    /// Record (or overwrite) the outcome of a test.
    func record(_ result: TestResult) {
        results[result.category] = result
    }

    func reset() {
        for category in TestCategory.allCases {
            results[category] = TestResult(category: category)
        }
    }

    var completedCount: Int {
        results.values.filter { $0.outcome != .notRun }.count
    }

    var totalCount: Int { TestCategory.allCases.count }

    /// Overall device health, 0–100, weighted across tests that actually ran.
    /// Unsupported / not-run tests are excluded so they don't unfairly lower it.
    var healthScore: Int {
        let contributions = results.values.map { $0.outcome.scoreContribution }
        let possible = contributions.reduce(0) { $0 + $1.possible }
        guard possible > 0 else { return 0 }
        let earned = contributions.reduce(0) { $0 + $1.earned }
        return Int((Double(earned) / Double(possible) * 100).rounded())
    }

    /// Results in dashboard order.
    var orderedResults: [TestResult] {
        TestCategory.allCases.map { result(for: $0) }
    }
}
