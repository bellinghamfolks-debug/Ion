import SwiftUI

@main
struct PDFToWordApp: App {
    @StateObject private var appModel = AppModel()
    @StateObject private var settings = AppSettings()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appModel)
                .environmentObject(settings)
        }
    }
}
