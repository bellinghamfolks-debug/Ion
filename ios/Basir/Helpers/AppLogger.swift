// AppLogger.swift
// Privacy-aware unified logging. User document text, API keys, images,
// and proxy tokens must never be written to logs.

import Foundation
import OSLog

enum AppLogger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.basir.ai"
    private static let general = Logger(subsystem: subsystem, category: "general")
    private static let network = Logger(subsystem: subsystem, category: "network")
    private static let documents = Logger(subsystem: subsystem, category: "documents")

    static func info(_ message: String) {
        general.info("\(message, privacy: .public)")
    }

    static func networkError(_ message: String) {
        network.error("\(message, privacy: .public)")
    }

    static func documentError(_ message: String) {
        documents.error("\(message, privacy: .public)")
    }
}
