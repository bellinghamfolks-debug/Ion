import SwiftUI

/// Accessible settings, including the LANGUAGE CHOICE (System / English /
/// Arabic). Choosing Arabic localizes the interface and the spoken guidance; it
/// does not force-convert anything the user didn't ask for.
struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        Form {
            Section(settings.t("Language")) {
                Picker(settings.t("Language"), selection: $settings.language) {
                    ForEach(AppLanguage.allCases) { lang in
                        Text(lang == .system ? settings.t("System") : lang.displayNativeName)
                            .tag(lang)
                    }
                }
                .accessibilityLabel(settings.t("Language"))
            }

            Section(settings.t("Appearance")) {
                Picker(settings.t("Interface Mode"), selection: $settings.interfaceMode) {
                    Text(settings.t("Blind")).tag("Blind")
                    Text(settings.t("Low Vision")).tag("Low Vision")
                    Text(settings.t("Standard")).tag("Standard")
                }
            }

            Section(settings.t("Speech Detail")) {
                Picker(settings.t("Speech Detail"), selection: $settings.verbosity) {
                    Text(settings.t("Minimal")).tag(Verbosity.minimal)
                    Text(settings.t("Normal")).tag(Verbosity.normal)
                    Text(settings.t("Detailed")).tag(Verbosity.detailed)
                }
                Toggle(settings.t("Haptic-first leveling"), isOn: $settings.hapticFirst)
                    .accessibilityHint(settings.t("Reserve speech for framing; use haptics for leveling."))
                Toggle(settings.t("Auto capture when ready"), isOn: $settings.autoCapture)
                    .accessibilityHint(settings.t("Captures automatically when level, sharp, and framed."))
            }

            Section(settings.t("Authenticity")) {
                Text(settings.t("The Fix Photo workflow only rotates, corrects perspective, and crops. It never uses generative AI."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(settings.t("Settings"))
    }
}
