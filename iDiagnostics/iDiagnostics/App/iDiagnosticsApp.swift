import SwiftUI

@main
struct iDiagnosticsApp: App {
    @StateObject private var store = DiagnosticsStore()

    var body: some Scene {
        WindowGroup {
            DashboardView()
                .environmentObject(store)
                .environment(\.layoutDirection, .rightToLeft)
        }
    }
}
