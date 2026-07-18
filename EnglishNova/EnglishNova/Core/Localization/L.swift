import Foundation

/// Localize an Arabic source string at runtime via Localizable.strings.
///
/// SwiftUI localizes *literal* strings passed to Text/Label/Button automatically,
/// but not String values that are stored or computed (enum titles, model labels).
/// For those, call `L("العربية")` so they resolve to English in English mode and
/// fall back to the Arabic key otherwise.
func L(_ arabic: String) -> String { NSLocalizedString(arabic, comment: "") }
