import Foundation

/// LTE and 5G-NR band catalogues plus the bitmask maths ZTE uses for band
/// locking. ZTE encodes a set of bands as a hex bitmask where band *n* sets
/// bit (n-1); the mask is sent as an upper-case hex string.
enum RadioBand {
    /// LTE bands commonly used across MENA / Gulf operators (plus a broad set).
    static let lte: [Int] = [1, 2, 3, 4, 5, 7, 8, 12, 13, 17, 18, 19, 20,
                             25, 26, 28, 32, 38, 40, 41, 42, 43, 66]

    /// 5G NR bands (sub-6) common on Gulf 5G networks.
    static let nr5g: [Int] = [1, 3, 5, 7, 8, 20, 28, 38, 40, 41, 66, 71, 77, 78, 79]

    /// A short human hint for bands frequently useful for *range* in remote
    /// areas (low-band penetrates farther). Shown as a tip in the UI.
    static let longRangeHint: Set<Int> = [5, 8, 12, 13, 17, 18, 19, 20, 28, 71]

    /// Build the ZTE hex bitmask for a set of band numbers.
    /// Example: bands {3, 20} -> bit2 + bit19 -> 0x80004 -> "80004".
    static func hexMask(for bands: Set<Int>) -> String {
        var mask: UInt64 = 0
        for b in bands where b >= 1 && b <= 64 {
            mask |= (UInt64(1) << UInt64(b - 1))
        }
        return String(mask, radix: 16, uppercase: true)
    }

    /// Decode a ZTE hex bitmask back into the set of band numbers.
    static func bands(fromHexMask hex: String) -> Set<Int> {
        let cleaned = hex.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "0x", with: "")
        guard let mask = UInt64(cleaned, radix: 16) else { return [] }
        var result: Set<Int> = []
        for b in 1...64 where (mask & (UInt64(1) << UInt64(b - 1))) != 0 {
            result.insert(b)
        }
        return result
    }
}

/// The radio access technology the modem should be allowed to use.
enum NetworkMode: String, CaseIterable, Identifiable {
    case auto
    case lteOnly
    case nr5gOnly
    case lteAnd5g

    var id: String { rawValue }

    /// Arabic label for the picker.
    var titleAr: String {
        switch self {
        case .auto:     return "تلقائي (الأفضل)"
        case .lteOnly:  return "4G فقط"
        case .nr5gOnly: return "5G فقط"
        case .lteAnd5g: return "4G + 5G"
        }
    }

    /// Value sent as `BearerPreference` to goformId=SET_BEARER_PREFERENCE.
    /// These are the most widely documented ZTE values; if a firmware rejects
    /// one, the Diagnostics log shows the raw response so it can be adjusted.
    var bearerPreference: String {
        switch self {
        case .auto:     return "NETWORK_auto"
        case .lteOnly:  return "Only_LTE"
        case .nr5gOnly: return "Only_NR5G"
        case .lteAnd5g: return "LTE_AND_NR5G"
        }
    }
}
