import AppIntents
import Foundation

/// Intents shared with the BasirLiveActivity extension so they can sit in
/// Control Center, on the Lock Screen and on the Action button. They always
/// open the app, so `perform` runs in the app process, where the router is.

struct StartGuidedCaptureIntent: AppIntent {
    static var title: LocalizedStringResource = "Scan a Document with Basir"
    static var description = IntentDescription(
        "Opens Basir's guided camera, which tells you how to move the phone until the whole page is in view."
    )
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !BASIR_EXTENSION
        IntentRouter.shared.pendingAction = .guidedCapture
        #endif
        return .result()
    }
}

struct ReadLatestResultIntent: AppIntent {
    static var title: LocalizedStringResource = "Read the Latest Basir Result"
    static var description = IntentDescription("Opens the most recent Word file in Basir's reader, where you stopped.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !BASIR_EXTENSION
        IntentRouter.shared.pendingAction = .readLatestResult
        #endif
        return .result()
    }
}

/// The latest finished result, as the widget shows it. The app writes it to
/// the shared App Group whenever its library changes.
struct LatestResultSnapshot: Codable, Equatable {
    static let appGroup = "group.com.basir.convert.ios"
    static let defaultsKey = "latestResultSnapshot"
    static let widgetKind = "BasirLatestResult"

    var fileName: String
    var createdAt: Date
    var isTranslation: Bool
    var isArabic: Bool

    static func load() -> LatestResultSnapshot? {
        guard let data = UserDefaults(suiteName: appGroup)?.data(forKey: defaultsKey) else { return nil }
        return try? JSONDecoder().decode(LatestResultSnapshot.self, from: data)
    }

    /// Returns true when the stored value changed.
    @discardableResult
    static func store(_ snapshot: LatestResultSnapshot?) -> Bool {
        guard let defaults = UserDefaults(suiteName: appGroup) else { return false }
        guard snapshot != load() else { return false }
        if let snapshot, let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: defaultsKey)
        } else {
            defaults.removeObject(forKey: defaultsKey)
        }
        return true
    }
}

/// basir://scan and basir://latest, used by the widget and the control.
enum BasirLink: String {
    case scan
    case latest

    var url: URL { URL(string: "basir://\(rawValue)")! }

    init?(url: URL) {
        guard url.scheme?.lowercased() == "basir", let host = url.host?.lowercased() else { return nil }
        self.init(rawValue: host)
    }
}
