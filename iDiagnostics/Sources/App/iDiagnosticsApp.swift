import SwiftUI

@main
struct iDiagnosticsApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store = DiagnosticsStore()

    var body: some Scene {
        WindowGroup {
            DashboardView()
                .environmentObject(store)
                .environment(\.layoutDirection, .rightToLeft)
                .alert("تنبيه الحفظ", isPresented: persistenceAlertBinding) {
                    Button("حسنًا", role: .cancel) {
                        store.persistenceAlert = nil
                    }
                } message: {
                    Text(store.persistenceAlert ?? "")
                }
        }
        .onChange(of: scenePhase) { phase in
            if phase != .active {
                store.saveNow()
            }
        }
    }

    private var persistenceAlertBinding: Binding<Bool> {
        Binding(
            get: { store.persistenceAlert != nil },
            set: { if !$0 { store.persistenceAlert = nil } }
        )
    }
}
