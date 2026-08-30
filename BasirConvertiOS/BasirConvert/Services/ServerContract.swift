import Foundation

enum BasirAPIContract {
    static let identifier = "api_contract_v3"

    static func accepts(apiContract: String, capabilities: Set<String>) -> Bool {
        apiContract.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == identifier
            || capabilities.contains(identifier)
    }
}

