import Foundation
import WatchConnectivity

/// Sends the usual drink and favorites to the watch, and makes the drink the
/// watch asks for. "Your drink is ready" reaches the wrist through the
/// phone's own notification.
@MainActor
final class WatchBridge: NSObject, WCSessionDelegate {
    static let shared = WatchBridge()

    struct Item: Codable { let id: String; let name: String }

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Updates what the watch shows.
    func publish(model: AppModel) {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated,
              WCSession.default.isPaired, WCSession.default.isWatchAppInstalled else { return }
        var items = [Item(id: "usual", name: L("ready.usual", model.usualRecipe.displayName))]
        items += model.activeProfile.favorites.prefix(8).map { Item(id: $0.id.uuidString, name: $0.displayName) }
        let status = model.connection.isConnected ? model.snapshot.spokenStatus : model.connection.title
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? WCSession.default.updateApplicationContext(["items": data, "status": status, "arabic": AppLanguage.current == .arabic])
    }

    private func handle(_ id: String) async -> String {
        let model = AppModel.shared
        model.start()
        let recipe = id == "usual" ? model.usualRecipe : model.activeProfile.favorites.first { $0.id.uuidString == id }
        guard let recipe else { return L("intent.noFavorite") }
        do { try await IntentSupport.waitForConnection(model) } catch { return L("error.notConnected") }
        let started = await model.brew(recipe)
        return started ? L("intent.brewing", recipe.displayName) : (model.lastMessage ?? L("intent.failed"))
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        Task { @MainActor in self.publish(model: AppModel.shared) }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        guard let id = message["brew"] as? String else { replyHandler([:]); return }
        Task { @MainActor in
            let text = await self.handle(id)
            replyHandler(["text": text])
        }
    }
}
