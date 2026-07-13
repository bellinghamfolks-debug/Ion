import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: RouterSettings
    @EnvironmentObject private var model: RouterViewModel
    @State private var showPassword = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("عنوان الراوتر")
                        Spacer()
                        TextField("192.168.0.1", text: $settings.host)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.numbersAndPunctuation)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .environment(\.layoutDirection, .leftToRight)
                    }
                    HStack {
                        Text("كلمة المرور")
                        Spacer()
                        Group {
                            if showPassword {
                                TextField("admin password", text: $settings.password)
                            } else {
                                SecureField("admin password", text: $settings.password)
                            }
                        }
                        .multilineTextAlignment(.trailing)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .environment(\.layoutDirection, .leftToRight)
                        Button { showPassword.toggle() } label: {
                            Image(systemName: showPassword ? "eye.slash" : "eye")
                        }
                    }
                } header: {
                    Text("الاتصال بالراوتر")
                } footer: {
                    Text("اتصل بشبكة الواي فاي الخاصة بجهاز ZTE MU5001 أولًا، ثم أدخل كلمة مرور صفحة الإدارة (نفسها المكتوبة عادة أسفل الجهاز).")
                }

                Section {
                    Button("اتصال وتسجيل الدخول") { Task { await model.connect() } }
                        .disabled(settings.password.isEmpty)
                }

                Section("عن التطبيق") {
                    Text("تطبيق للتحكم في نطاقات (ترددات) جهاز ZTE MU5001 عبر واجهة الإدارة المحلية، لاختيار النطاق الأفضل في المناطق ضعيفة التغطية.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("الإعدادات")
        }
    }
}
