import SwiftUI

struct ContentView: View {
    @EnvironmentObject var settings: BasirSettings
    @EnvironmentObject var shareInbox: ShareInbox
    @State private var selectedTab: AppTab = .talk

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                .tabItem {
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                    Text(L10n.t("المحادثة", "Chat"))
                }
                .tag(AppTab.talk)

            VisionView()
                .tabItem {
                    Image(systemName: "eye.fill")
                    Text(L10n.t("الرؤية", "Vision"))
                }
                .tag(AppTab.vision)

            DocumentsView()
                .tabItem {
                    Image(systemName: "doc.text.fill")
                    Text(L10n.t("المستندات", "Documents"))
                }
                .tag(AppTab.documents)

            MoreView()
                .tabItem {
                    Image(systemName: "square.grid.2x2.fill")
                    Text(L10n.t("المزيد", "More"))
                }
                .tag(AppTab.more)
        }
        .tint(BasirTheme.brand)
        .onChange(of: selectedTab) { _, newTab in
            UIAccessibility.post(notification: .announcement, argument: newTab.spokenName)
        }
        .sheet(item: $shareInbox.pending) { item in
            SharedItemView(incoming: item)
        }
    }
}

enum AppTab: Hashable {
    case talk, vision, documents, more

    var spokenName: String {
        switch self {
        case .talk: return L10n.t("تبويب المحادثة", "Chat tab")
        case .vision: return L10n.t("تبويب الرؤية", "Vision tab")
        case .documents: return L10n.t("تبويب المستندات", "Documents tab")
        case .more: return L10n.t("تبويب المزيد", "More tab")
        }
    }
}
