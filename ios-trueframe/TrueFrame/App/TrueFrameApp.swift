import SwiftUI

@main
struct TrueFrameApp: App {
    var body: some Scene {
        WindowGroup {
            HomeView()
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
