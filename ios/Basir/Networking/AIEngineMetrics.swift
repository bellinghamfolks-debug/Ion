import Foundation

struct AIUsageMetadata: Codable, Equatable {
    let promptTokenCount: Int?
    let candidatesTokenCount: Int?
    let totalTokenCount: Int?
    let thoughtsTokenCount: Int?
    let cachedContentTokenCount: Int?

    static let empty = AIUsageMetadata(
        promptTokenCount: nil,
        candidatesTokenCount: nil,
        totalTokenCount: nil,
        thoughtsTokenCount: nil,
        cachedContentTokenCount: nil
    )
}

struct AIGenerationResult {
    let text: String
    let modelVersion: String?
    let usage: AIUsageMetadata
}

struct AIEngineMetric: Codable {
    let timestamp: Date
    let requestID: String
    let task: String
    let transport: String
    let requestedModel: String?
    let executedModel: String?
    let durationMilliseconds: Int
    let attempt: Int
    let success: Bool
    let failureCategory: String?
    let promptTokens: Int?
    let outputTokens: Int?
    let thoughtsTokens: Int?
    let totalTokens: Int?
}

actor AIEngineMetricsStore {
    static let shared = AIEngineMetricsStore()
    private let maximumRecords = 250
    private let encoder: JSONEncoder = {
        let value = JSONEncoder()
        value.dateEncodingStrategy = .iso8601
        return value
    }()

    private var fileURL: URL? {
        guard let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }
        return directory.appendingPathComponent("basir-ai-metrics.jsonl")
    }

    func record(_ metric: AIEngineMetric) {
        guard let fileURL, let encoded = try? encoder.encode(metric),
              let line = String(data: encoded, encoding: .utf8) else { return }
        var lines: [String] = []
        if let existing = try? String(contentsOf: fileURL, encoding: .utf8) {
            lines = existing.split(separator: "\n").suffix(maximumRecords - 1).map(String.init)
        }
        lines.append(line)
        let payload = lines.joined(separator: "\n") + "\n"
        try? payload.write(to: fileURL, atomically: true, encoding: .utf8)
        #if os(iOS)
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: fileURL.path
        )
        #endif
    }
}
