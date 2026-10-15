import XCTest
@testable import BasirConvert

/// Translation preferences reach the server exactly, only for translations.
@MainActor
final class TranslationPreferencesTests: XCTestCase {
    func testTheServersFieldNamesAndOnlyUsableGlossaryEntries() throws {
        var prefs = TranslationPreferences()
        prefs.style = .plain
        prefs.numerals = .eastern
        prefs.terms = .translateWithOriginal
        prefs.sourceLanguage = "fr"
        prefs.glossary = [.init(source: " Basir ", target: "بصير"), .init(source: "", target: "x"),
                          .init(source: "same", target: "same")]
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(prefs.payload)) as? [String: Any])
        XCTAssertEqual(json["style"] as? String, "plain")
        XCTAssertEqual(json["numerals"] as? String, "eastern")
        XCTAssertEqual(json["terms"] as? String, "translate_with_original")
        XCTAssertEqual(json["source_language"] as? String, "fr")
        XCTAssertEqual(json["image_text"] as? String, "translate")
        let glossary = try XCTUnwrap(json["glossary"] as? [[String: String]])
        XCTAssertEqual(glossary, [["source": "Basir", "target": "بصير"]])
    }

    func testDefaultsMatchTheServersDefaults() throws {
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(TranslationPreferences.standard.payload)) as? [String: Any])
        XCTAssertEqual(json["style"] as? String, "faithful")
        XCTAssertEqual(json["formality"] as? String, "formal")
        XCTAssertEqual(json["names"] as? String, "keep")
        XCTAssertEqual(json["quotations"] as? String, "keep")
        XCTAssertEqual(json["numerals"] as? String, "source")
        XCTAssertEqual(json["notes"] as? Bool, false)
    }

    func testThePreferencesAreRememberedAndSurviveARelaunch() {
        let name = "translation-\(UUID().uuidString)"
        let settings = SettingsStore(defaults: UserDefaults(suiteName: name)!)
        XCTAssertEqual(settings.translation, .standard)
        settings.translation.style = .natural
        settings.translation.glossary = [.init(source: "app", target: "تطبيق")]
        settings.save(defaults: UserDefaults(suiteName: name)!)
        let reloaded = SettingsStore(defaults: UserDefaults(suiteName: name)!)
        XCTAssertEqual(reloaded.translation.style, .natural)
        XCTAssertEqual(reloaded.translation.usableGlossary.map(\.target), ["تطبيق"])
    }

    func testTheSummaryLineSaysWhatChanged() {
        let l10n = L10n()
        l10n.language = .arabic
        XCTAssertTrue(TranslationPreferences.standard.summary(l10n).contains("الافتراضية"))
        var prefs = TranslationPreferences()
        prefs.numerals = .eastern
        prefs.notes = true
        let line = prefs.summary(l10n)
        XCTAssertTrue(line.contains("٠١٢٣"))
        XCTAssertTrue(line.contains("ملاحظات المترجم"))
    }
}
