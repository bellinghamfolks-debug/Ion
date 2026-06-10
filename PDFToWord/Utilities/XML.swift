import Foundation

enum XML {
    static func escape(_ value: String) -> String {
        let cleaned = value.unicodeScalars.filter { scalar in
            scalar.value == 0x9 || scalar.value == 0xA || scalar.value == 0xD || scalar.value >= 0x20
        }.map(String.init).joined()

        return cleaned
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    static func containsArabic(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            (0x0600...0x06FF).contains(scalar.value) ||
            (0x0750...0x077F).contains(scalar.value) ||
            (0x08A0...0x08FF).contains(scalar.value) ||
            (0xFB50...0xFDFF).contains(scalar.value) ||
            (0xFE70...0xFEFF).contains(scalar.value)
        }
    }
}
