import AppIntents
import Foundation

// Siri and Shortcuts added in version 3.

struct MachineNeedsIntent: AppIntent {
    static var title: LocalizedStringResource = "What does the machine need?"
    static var description = IntentDescription("Says what the machine needs now and which care is due next.")
    static var openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let model = AppModel.shared
        model.start()
        try? await IntentSupport.waitForConnection(model, seconds: 6)
        var parts: [String] = []
        if model.connection.isConnected {
            let alarms = model.snapshot.alarms
            parts.append(alarms.isEmpty ? L("needs.nothing") : L("needs.alarms", alarms.map(\.title).joined(separator: L("list.separator"))))
        }
        if let next = model.forecast.items.first {
            parts.append(L("needs.nextCare", next.task.title, next.daysLeft))
        }
        return .result(dialog: IntentDialog(stringLiteral: parts.joined(separator: L("sentence.separator"))))
    }
}

struct CaffeineTodayIntent: AppIntent {
    static var title: LocalizedStringResource = "Caffeine today"
    static var description = IntentDescription("Says today's estimated caffeine and how much is still in your body.")
    static var openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let model = AppModel.shared
        let remaining = CaffeineEstimator.remaining(history: model.activeProfile.history, spilled: Set(model.data.life.pro.spilled),
                                                   decafBeans: model.decafBeanIDs)
        let text = L("intent.caffeine", model.caffeineToday, model.caffeineLimitToday, remaining)
        return .result(dialog: IntentDialog(stringLiteral: text))
    }
}

struct OpenedNewBagIntent: AppIntent {
    static var title: LocalizedStringResource = "I opened a new bag of beans"
    static var description = IntentDescription("Dates the bag in the hopper as opened today and logs the purchase.")
    static var openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: IntentDialog(stringLiteral: AppModel.shared.openedNewBag()))
    }
}

struct SwitchPersonIntent: AppIntent {
    static var title: LocalizedStringResource = "Switch coffee profile"
    static var description = IntentDescription("Switches to the profile with this name, e.g. \"I am Sara\".")
    static var openAppWhenRun = false

    @Parameter(title: "Name")
    var name: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let model = AppModel.shared
        let wanted = DrinkQuery.normalize(name)
        guard let profile = model.data.profiles.first(where: { DrinkQuery.normalize($0.name) == wanted })
                ?? model.data.profiles.first(where: { DrinkQuery.normalize($0.name).contains(wanted) || wanted.contains(DrinkQuery.normalize($0.name)) }) else {
            return .result(dialog: IntentDialog(stringLiteral: L("intent.noProfile", name)))
        }
        if model.data.guestMode { model.setGuestMode(false) }
        model.selectProfile(profile.id)
        return .result(dialog: IntentDialog(stringLiteral: L("announce.profileSelected", profile.name)))
    }
}

struct TurnOffMachineIntent: AppIntent {
    static var title: LocalizedStringResource = "Turn off the machine"
    static var openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let model = AppModel.shared
        model.start()
        try await IntentSupport.waitForConnection(model)
        await model.powerOff()
        return .result(dialog: IntentDialog(stringLiteral: L("announce.turningOff")))
    }
}

struct DrinkForNowIntent: AppIntent {
    static var title: LocalizedStringResource = "Make the right coffee for now"
    static var description = IntentDescription("Morning: your usual. Afternoon: a lighter one. Late: something without caffeine.")
    static var openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let model = AppModel.shared
        model.start()
        let hour = Calendar.current.component(.hour, from: Date())
        let recipe = DrinkForNow.recipe(for: model.data, hour: hour, cutoffHour: model.ramadanActive ? -1 : model.settings.caffeineCutoffHour)
        try await IntentSupport.waitForConnection(model)
        let started = await model.brew(recipe)
        let text = started ? L("intent.brewing", recipe.spokenSummary) : (model.lastMessage ?? L("intent.failed"))
        return .result(dialog: IntentDialog(stringLiteral: text))
    }
}

/// A Focus filter: while a chosen Focus (Sleep, Work…) is on, no sounds and
/// no speech without VoiceOver.
struct CoffeeFocusFilter: SetFocusFilterIntent {
    static var title: LocalizedStringResource = "Coffee: quiet"
    static var description: IntentDescription? = IntentDescription("Silences the app's sounds and spoken announcements while this Focus is on.")

    @Parameter(title: "Quiet sounds and speech", default: false)
    var quiet: Bool

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: quiet ? "Quiet" : "Normal")
    }

    func perform() async throws -> some IntentResult {
        UserDefaults(suiteName: SharedCoffee.appGroup)?.set(quiet, forKey: FocusFilterState.key)
        let value = quiet
        await MainActor.run { Announcer.shared.focusQuiet = value }
        return .result()
    }
}
