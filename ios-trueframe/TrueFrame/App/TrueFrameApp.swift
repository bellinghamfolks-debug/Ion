import SwiftUI

@main
struct TrueFrameApp: App {
    @StateObject private var settings = AppSettings.shared

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(settings)
                .environment(\.locale, Locale(identifier: settings.effectiveCode))
                .environment(\.layoutDirection, settings.layoutDirection)
        }
    }
}

/// User-selectable accessibility profile.
enum InterfaceMode: String, CaseIterable, Identifiable {
    case blind = "Blind"
    case lowVision = "Low Vision"
    case standard = "Standard"
    var id: String { rawValue }
}
