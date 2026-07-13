import Foundation
import Combine

/// A rolling, on-device log of every request/response exchanged with the
/// router. This is the safety net for the firmware-variability problem: if a
/// band-lock command is rejected, the raw response is right here to inspect.
@MainActor
final class DiagnosticsLog: ObservableObject {
    static let shared = DiagnosticsLog()

    enum Kind: String { case request = "→", response = "←", note = "•" }

    struct Entry: Identifiable {
        let id = UUID()
        let time: Date
        let kind: Kind
        let text: String
    }

    @Published private(set) var entries: [Entry] = []
    private let limit = 300

    func add(_ kind: Kind, _ text: String) {
        entries.append(Entry(time: Date(), kind: kind, text: text))
        if entries.count > limit { entries.removeFirst(entries.count - limit) }
    }

    func clear() { entries.removeAll() }

    var exportText: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm:ss"
        return entries.map { "\(fmt.string(from: $0.time)) \($0.kind.rawValue) \($0.text)" }
            .joined(separator: "\n")
    }
}
