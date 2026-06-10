import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        TabView {
            ConvertView()
                .tabItem { Label(L10n.text("التحويل"), systemImage: "doc.badge.arrow.up") }

            HistoryView()
                .tabItem { Label(L10n.text("السجل"), systemImage: "clock.arrow.circlepath") }

            SettingsView()
                .tabItem { Label(L10n.text("الإعدادات"), systemImage: "slider.horizontal.3") }
        }
        .alert(L10n.text("تنبيه"), isPresented: alertBinding) {
            Button(L10n.text("حسنًا"), role: .cancel) {}
        } message: {
            Text(appModel.alertMessage ?? "")
        }
    }

    private var alertBinding: Binding<Bool> {
        Binding(
            get: { appModel.alertMessage != nil },
            set: { if !$0 { appModel.alertMessage = nil } }
        )
    }
}
