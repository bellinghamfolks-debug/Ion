import SwiftUI
import WatchConnectivity
import WidgetKit

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

    func brew(_ id: String) { send(["brew": id]) }
    func routine() { send(["routine": true]) }
    func stop() { send(["stop": true]) }

    private func send(_ payload: [String: Any]) {
        guard WCSession.default.isReachable else {
            message = t("افتح قهوتي على الهاتف أو قرّبه", "Open Coffee on your iPhone or bring it closer")
            return
        }
        message = t("جارٍ الطلب…", "Asking…")
        WCSession.default.sendMessage(payload, replyHandler: { reply in
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
        // For the complications, which read the shared app group.
        let shared = UserDefaults(suiteName: WatchShared.group)
        shared?.set(status, forKey: WatchShared.status)
        shared?.set(context["caffeine"] as? String ?? "", forKey: WatchShared.caffeine)
        shared?.set(context["care"] as? String ?? "", forKey: WatchShared.care)
        shared?.set(context["ready"] as? Bool ?? false, forKey: WatchShared.ready)
        shared?.set(arabic, forKey: WatchShared.arabic)
        WidgetCenter.shared.reloadAllTimelines()
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
                Button { link.routine() } label: {
                    Label(link.t("روتين الصباح", "Morning routine"), systemImage: "sunrise.fill")
                }
                .accessibilityHint(link.t("يشغّل الماكينة ثم يحضّر مشروبك المعتاد", "Turns the machine on, then makes your usual"))
                Button(role: .destructive) { link.stop() } label: {
                    Label(link.t("إيقاف المشروب", "Stop the drink"), systemImage: "stop.fill")
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

/// Keys shared with the watch complications.
enum WatchShared {
    static let group = "group.com.coffeeaccess.app"
    static let status = "watch.status"
    static let caffeine = "watch.caffeine"
    static let care = "watch.care"
    static let ready = "watch.ready"
    static let arabic = "watch.arabic"
}
