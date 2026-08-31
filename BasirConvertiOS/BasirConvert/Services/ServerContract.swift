import Foundation

enum BasirAPIContract {
    static let identifier = "api_contract_v3"

    static func accepts(apiContract: String, capabilities: Set<String>) -> Bool {
        apiContract.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == identifier
            || capabilities.contains(identifier)
    }

    /// The natural Markdown engine can legitimately omit blank source pages and
    /// preserve a partial result when isolated pages fail. Validate those three
    /// disjoint source-page buckets instead of requiring the legacy PageIR
    /// physical-page accounting fields.
    static func naturalPageAccountingIsValid(
        expectedSelectedPages: Int,
        retained: [Int],
        skippedBlank: [Int],
        failed: [Int]
    ) -> Bool {
        let retainedSet = Set(retained)
        let skippedSet = Set(skippedBlank)
        let failedSet = Set(failed)

        guard retainedSet.count == retained.count,
              skippedSet.count == skippedBlank.count,
              failedSet.count == failed.count else {
            return false
        }
        guard retainedSet.allSatisfy({ $0 > 0 }),
              skippedSet.allSatisfy({ $0 > 0 }),
              failedSet.allSatisfy({ $0 > 0 }) else {
            return false
        }
        guard retainedSet.isDisjoint(with: skippedSet),
              retainedSet.isDisjoint(with: failedSet),
              skippedSet.isDisjoint(with: failedSet) else {
            return false
        }

        guard expectedSelectedPages > 0 else { return true }
        return retainedSet.count + skippedSet.count + failedSet.count == expectedSelectedPages
    }
}
