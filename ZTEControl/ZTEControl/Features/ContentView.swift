import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: RouterViewModel
    @EnvironmentObject private var settings: RouterSettings

    var body: some View {
        TabView {
            DashboardView()
                .tabItem { Label("الإشارة", systemImage: "antenna.radiowaves.left.and.right") }
            BandLockView()
                .tabItem { Label("النطاقات", systemImage: "slider.horizontal.3") }
            DiagnosticsView()
                .tabItem { Label("السجل", systemImage: "doc.text.magnifyingglass") }
            SettingsView()
                .tabItem { Label("الإعدادات", systemImage: "gearshape") }
        }
        .task {
            // Auto-connect on launch if a password is already saved.
            if !settings.password.isEmpty, !model.isConnected {
                await model.connect()
            }
        }
    }
}
