import Foundation
import OSLog
import UIKit

enum AppLog {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.bellinghamfolks.idiagnostics"
    static let lifecycle = Logger(subsystem: subsystem, category: "lifecycle")
    static let persistence = Logger(subsystem: subsystem, category: "persistence")
    static let diagnostics = Logger(subsystem: subsystem, category: "diagnostics")
    static let media = Logger(subsystem: subsystem, category: "media")
}

enum AccessibilityAnnouncer {
    static func post(_ message: String) {
        DispatchQueue.main.async {
            guard UIAccessibility.isVoiceOverRunning else { return }
            UIAccessibility.post(notification: .announcement, argument: message)
        }
    }
}
