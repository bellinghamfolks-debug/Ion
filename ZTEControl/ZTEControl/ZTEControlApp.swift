import SwiftUI

@main
struct ZTEControlApp: App {
    @StateObject private var settings = RouterSettings.shared
    @StateObject private var model = RouterViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(settings)
                .environmentObject(model)
                .environment(\.layoutDirection, .rightToLeft)
        }
    }
}
