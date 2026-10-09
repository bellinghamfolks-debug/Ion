import Foundation

/// Coffee words explained in plain language.
enum GlossaryTerm: String, CaseIterable, Identifiable {
    case crema, ristretto, lungo, doppio, aroma, grind, extraction, brewingUnit, descaling
    case beanAdapt, roast, arabica, robusta, microfoam, latteArt, coldBrew, decaf, bloom, tamping, waterHardness

    var id: String { rawValue }
    var title: String { L("glossary.\(rawValue).title") }
    var body: String { L("glossary.\(rawValue).body") }
}

/// Short lessons, each with two questions.
enum AcademyLesson: String, CaseIterable, Identifiable {
    case beans, grind, milk, strength, water, care

    var id: String { rawValue }
    var title: String { L("academy.\(rawValue).title") }
    var paragraphs: [String] { (1...3).map { L("academy.\(rawValue).p\($0)") } }
    var questions: [AcademyQuestion] { (1...2).map { AcademyQuestion(lesson: self, number: $0) } }
}

struct AcademyQuestion: Identifiable, Equatable {
    let lesson: AcademyLesson
    let number: Int
    var id: String { "\(lesson.rawValue).\(number)" }
    var prompt: String { L("academy.\(lesson.rawValue).q\(number)") }
    /// Three choices; the first one written is the right one, shown shuffled.
    var choices: [String] { (1...3).map { L("academy.\(lesson.rawValue).q\(number).a\($0)") } }
    var correct: String { choices[0] }
    var shuffled: [String] {
        let seed = abs(id.unicodeScalars.reduce(0) { $0 &* 31 &+ Int($1.value) })
        let order = [[0, 1, 2], [1, 0, 2], [2, 0, 1], [1, 2, 0]][seed % 4]
        return order.map { choices[$0] }
    }
}

/// What is new in this version, shown once after an update.
enum WhatsNew {
    static let version = "3.0.0"
    static let count = 8
    static var items: [(title: String, body: String)] {
        (1...count).map { (L("whatsNew.\($0).title"), L("whatsNew.\($0).body")) }
    }
}

/// The help shown by the "?" button on each screen.
enum HelpTopic: String, CaseIterable, Identifiable {
    case home, drink, brewing, beans, machine, caffeine, household, hosting, settings, care

    var id: String { rawValue }
    var title: String { L("helpTopic.\(rawValue).title") }
    var body: String { L("helpTopic.\(rawValue).body") }
}

/// Everything the app can find by name: drinks, favorites, beans, care
/// guides, glossary words, signature recipes and screens.
struct SearchHit: Identifiable, Equatable {
    enum Kind: String { case drink, favorite, bean, guide, glossary, signature, screen }
    enum Target: Equatable {
        case drink(BeverageID), favorite(Recipe), bean(UUID), guide(MaintenanceGuideID), glossary(GlossaryTerm)
        case signature(SignatureRecipeID), screen(ProScreen)
    }

    var id: String
    var kind: Kind
    var title: String
    var subtitle: String
    var target: Target
}

enum GlobalSearch {
    static func normalized(_ text: String) -> String {
        DrinkQuery.normalize(text)
    }

    static func search(_ query: String, data: AppData) -> [SearchHit] {
        let needle = normalized(query)
        guard needle.count >= 2 else { return [] }
        func matches(_ values: String...) -> Bool { values.contains { normalized($0).contains(needle) } }
        var hits: [SearchHit] = []
        for favorite in data.activeProfile.favorites where matches(favorite.displayName, favorite.beverage.name) {
            hits.append(SearchHit(id: "fav-\(favorite.id)", kind: .favorite, title: favorite.displayName,
                                  subtitle: L("search.kind.favorite"), target: .favorite(favorite)))
        }
        for beverage in BeverageID.allCases where matches(beverage.name, beverage.rawValue) {
            hits.append(SearchHit(id: "drink-\(beverage.rawValue)", kind: .drink, title: beverage.name,
                                  subtitle: L("search.kind.drink"), target: .drink(beverage)))
        }
        for bean in data.beanProfiles where matches(bean.name, bean.roaster, bean.origin) {
            hits.append(SearchHit(id: "bean-\(bean.id)", kind: .bean, title: bean.name, subtitle: L("search.kind.bean"), target: .bean(bean.id)))
        }
        for guide in MaintenanceGuideID.allCases where matches(guide.title) {
            hits.append(SearchHit(id: "guide-\(guide.rawValue)", kind: .guide, title: guide.title, subtitle: L("search.kind.guide"), target: .guide(guide)))
        }
        for signature in SignatureRecipeID.allCases where matches(signature.title) {
            hits.append(SearchHit(id: "sig-\(signature.rawValue)", kind: .signature, title: signature.title,
                                  subtitle: L("search.kind.signature"), target: .signature(signature)))
        }
        for term in GlossaryTerm.allCases where matches(term.title, term.body) {
            hits.append(SearchHit(id: "term-\(term.rawValue)", kind: .glossary, title: term.title, subtitle: L("search.kind.glossary"), target: .glossary(term)))
        }
        for screen in ProScreen.allCases where matches(screen.title) {
            hits.append(SearchHit(id: "screen-\(screen.rawValue)", kind: .screen, title: screen.title, subtitle: L("search.kind.screen"), target: .screen(screen)))
        }
        return hits
    }
}

/// The screens added in version 3, so search and the hubs can open them.
enum ProScreen: String, CaseIterable, Identifiable, Hashable {
    case cups, organizer, combos, teaTimer, voPractice, purchases, compareBeans, alarmHistory, serviceReport
    case travel, supplies, profileNames, touchGuide, cupCheck, guestMenu, hosting, office, monthly, hourly
    case reduction, backup, historyEditor, privacy, glossary, academy, whatsNew, report, accessibility3, children, milk

    var id: String { rawValue }
    var title: String { L("screen.\(rawValue)") }
}
