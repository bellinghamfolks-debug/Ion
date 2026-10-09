import SwiftUI
import WatchConnectivity

/// The watch app: your usual and your favorites, one tap each. The phone
/// talks to the machine; the watch asks the phone.
@main
struct CoffeeWatchApp: App {
    @StateObject var link = WatchLink()

    var body: some Scene {
        WindowGroup {
            WatchHomeView().environmentObject(link)
        }
    }
}

struct WatchItem: Identifiable, Codable, Hashable {
    let id: String
    let name: String
}

@MainActor
final class WatchLink: NSObject, ObservableObject, WCSessionDelegate {
    @Published var items: [WatchItem] = []
    @Published var status = ""
    @Published var message: String?
    @Published var arabic = Locale.current.language.languageCode?.identifier == "ar"

    override init() {
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    func t(_ ar: String, _ en: String) -> String { arabic ? ar : en }

    func brew(_ id: String) {
        guard WCSession.default.isReachable else {
            message = t("افتح قهوتي على الهاتف أو قرّبه", "Open Coffee on your iPhone or bring it closer")
            return
        }
        message = t("جارٍ الطلب…", "Asking…")
        WCSession.default.sendMessage(["brew": id], replyHandler: { reply in
            let text = reply["text"] as? String ?? ""
            Task { @MainActor in self.message = text }
        }, errorHandler: { _ in
            Task { @MainActor in self.message = self.t("تعذّر الوصول إلى الهاتف", "Could not reach the iPhone") }
        })
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        let context = session.receivedApplicationContext
        Task { @MainActor in self.apply(context) }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) {
        Task { @MainActor in self.apply(context) }
    }

    private func apply(_ context: [String: Any]) {
        if let data = context["items"] as? Data, let decoded = try? JSONDecoder().decode([WatchItem].self, from: data) { items = decoded }
        if let status = context["status"] as? String { self.status = status }
        if let arabic = context["arabic"] as? Bool { self.arabic = arabic }
    }
}

struct WatchHomeView: View {
    @EnvironmentObject var link: WatchLink

    var body: some View {
        NavigationStack {
            List {
                if !link.status.isEmpty {
                    Text(link.status).font(.footnote)
                }
                if let message = link.message {
                    Text(message).font(.footnote).foregroundStyle(.orange)
                }
                if link.items.isEmpty {
                    Text(link.t("افتح قهوتي على الهاتف مرة واحدة لتظهر مشروباتك هنا.", "Open Coffee on your iPhone once to see your drinks here."))
                        .font(.footnote)
                }
                ForEach(link.items) { item in
                    Button { link.brew(item.id) } label: {
                        Label(item.name, systemImage: item.id == "usual" ? "cup.and.saucer.fill" : "star.fill")
                    }
                    .accessibilityHint(link.t("يحضّر هذا المشروب", "Makes this drink"))
                }
            }
            .navigationTitle(link.t("قهوتي", "Coffee"))
        }
        .environment(\.layoutDirection, link.arabic ? .rightToLeft : .leftToRight)
    }
}
