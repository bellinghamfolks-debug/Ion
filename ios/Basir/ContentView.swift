// ContentView.swift
// Root TabView. Mirrors Basir Android's bottom-nav with 4 tabs:
//   - Talk      (text Q&A + voice conversation)
//   - Vision    (image / scene description / math extraction)
//   - Documents (PDF/DOCX conversion + translation)
//   - More      (settings, archive, legal, about)

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
                    Text(L10n.t("اسأل", "Ask"))
                }
                .tag(AppTab.talk)
                .accessibilityLabel(L10n.t("اسأل", "Ask"))

            VisionView()
                .tabItem {
                    Image(systemName: "eye.fill")
                    Text(L10n.t("الصور", "Images"))
                }
                .tag(AppTab.vision)
                .accessibilityLabel(L10n.t("الصور", "Images"))

            DocumentsView()
                .tabItem {
                    Image(systemName: "doc.text.fill")
                    Text(L10n.t("المستندات", "Documents"))
                }
                .tag(AppTab.documents)
                .accessibilityLabel(L10n.t("المستندات", "Documents"))

            MoreView()
                .tabItem {
                    Image(systemName: "ellipsis.circle.fill")
                    Text(L10n.t("المزيد", "More"))
                }
                .tag(AppTab.more)
                .accessibilityLabel(L10n.t("المزيد", "More"))
        }
        .tint(.accentColor)
        // Make the tab change announcement explicit for VoiceOver users —
        // matches the Android announceForAccessibility in showHome().
        .onChange(of: selectedTab) { _, newTab in
            UIAccessibility.post(
                notification: .announcement,
                argument: newTab.spokenName
            )
        }
        // Present content shared into Basir from other apps.
        .sheet(item: $shareInbox.pending) { item in
            SharedItemView(incoming: item)
        }
    }
}

enum AppTab: Hashable {
    case talk, vision, documents, more

    var spokenName: String {
        switch self {
        case .talk:      return L10n.t("اسأل", "Ask")
        case .vision:    return L10n.t("الصور", "Images")
        case .documents: return L10n.t("المستندات", "Documents")
        case .more:      return L10n.t("المزيد", "More")
        }
    }
}
