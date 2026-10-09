import Foundation

/// What the shared quick intents do inside the app.
@MainActor
enum QuickActions {
    static func brewUsual() async -> String {
        let model = AppModel.shared
        model.start()
        let recipe = model.usualRecipe
        do { try await IntentSupport.waitForConnection(model) } catch { return L("error.notConnected") }
        let started = await model.brew(recipe)
        return started ? L("intent.brewing", recipe.spokenSummary) : (model.lastMessage ?? L("intent.failed"))
    }

    static func morningRoutine() async -> String {
        let model = AppModel.shared
        let recipe = model.usualRecipe
        await model.runRoutine(recipe, turnOnFirst: true)
        if let session = model.session, session.isRunning { return L("intent.brewing", recipe.spokenSummary) }
        return model.lastMessage ?? L("routine.notStarted")
    }

    static func stop() async {
        await AppModel.shared.stopBrewing()
    }
}
