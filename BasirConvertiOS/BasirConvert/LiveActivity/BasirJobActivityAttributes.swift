import ActivityKit
import Foundation

/// Shared between the app (which starts and updates the activity) and the
/// BasirLiveActivity widget extension (which draws it). Strings arrive
/// already localized so the extension needs no copy of the app's texts.
@available(iOS 16.1, *)
struct BasirJobActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// 0...4 for upload, read, verify, write Word, download; 5 when finished.
        var stepIndex: Int
        var stepTitle: String
        var statusText: String
        var percent: Int
        var isPaused: Bool
        var isFinished: Bool
        var succeeded: Bool
    }

    var fileName: String
    var isArabic: Bool
    /// Localized names of the five steps, in order.
    var stepNames: [String]
}
