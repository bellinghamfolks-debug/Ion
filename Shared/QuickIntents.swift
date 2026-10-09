import AppIntents
import Foundation

// Intents shared by the app and its widget extension, so they can be
// Control Center buttons, Action-button actions and Shortcuts automations
// ("when my alarm stops, make my coffee"). As Live Activity intents they
// always run in the app's own process, where the machine connection is.

struct BrewUsualIntent: AppIntent, LiveActivityIntent {
    static var title: LocalizedStringResource = "Make my usual coffee"
    static var description = IntentDescription("Makes your usual drink: the first favorite, or the drink you make most.")
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        #if COFFEE_WIDGET
        return .result(dialog: "")
        #else
        let text = await QuickActions.brewUsual()
        return .result(dialog: IntentDialog(stringLiteral: text))
        #endif
    }
}

struct MorningRoutineIntent: AppIntent, LiveActivityIntent {
    static var title: LocalizedStringResource = "Morning coffee routine"
    static var description = IntentDescription("Turns the machine on, waits until it is ready, then makes your usual drink.")
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        #if COFFEE_WIDGET
        return .result(dialog: "")
        #else
        let text = await QuickActions.morningRoutine()
        return .result(dialog: IntentDialog(stringLiteral: text))
        #endif
    }
}

struct StopBrewingIntent: AppIntent, LiveActivityIntent {
    static var title: LocalizedStringResource = "Stop the drink"
    static var description = IntentDescription("Stops the drink being made right now.")
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult {
        #if !COFFEE_WIDGET
        await QuickActions.stop()
        #endif
        return .result()
    }
}

/// One favorite from the medium widget, by its id.
struct BrewFavoriteByIDIntent: AppIntent, LiveActivityIntent {
    static var title: LocalizedStringResource = "Make a favorite drink"
    static var description = IntentDescription("Makes one of your favorites, chosen on the widget.")
    static var openAppWhenRun = false
    static var isDiscoverable = false

    @Parameter(title: "Favorite")
    var favoriteID: String

    init() {}

    init(favoriteID: String) {
        self.favoriteID = favoriteID
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        #if COFFEE_WIDGET
        return .result(dialog: "")
        #else
        let text = await QuickActions.brewFavorite(id: favoriteID)
        return .result(dialog: IntentDialog(stringLiteral: text))
        #endif
    }
}
