import Foundation

/// A bounded location in a captured frame. Unknown or malformed locations
/// never produce an affirmative direction or a "found" vibration.
struct ObjectLocation: Decodable, Equatable {
    let found: Bool
    let horizontal: String
    let vertical: String
    let landmark: String
    static func parse(_ answer: String) -> ObjectLocation? {
        let raw = answer.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "```json", with: "").replacingOccurrences(of: "```", with: "")
        guard let data = raw.data(using: .utf8), let value = try? JSONDecoder().decode(Self.self, from: data),
              ["left", "center", "right", "unknown"].contains(value.horizontal),
              ["upper", "middle", "lower", "unknown"].contains(value.vertical),
              !value.found || (value.horizontal != "unknown" && value.vertical != "unknown") else { return nil }
        return value
    }
    var pulseCount: Int { !found ? 0 : horizontal == "left" ? 2 : horizontal == "right" ? 3 : 1 }
}
