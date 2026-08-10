import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        Form {
            Section {
                Picker(settings.t("Language"), selection: $settings.language) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language == .system
                             ? settings.t("System")
                             : language.displayNativeName)
                            .tag(language)
                    }
                }
                .accessibilityLabel(settings.t("Language"))
            } header: {
                Text(settings.t("Language"))
            }

            Section {
                Picker(settings.t("Interface Mode"), selection: $settings.interfaceMode) {
                    Text(settings.t("Blind")).tag("Blind")
                    Text(settings.t("Low Vision")).tag("Low Vision")
                    Text(settings.t("Standard")).tag("Standard")
                }
                .pickerStyle(.segmented)
                .accessibilityLabel(settings.t("Interface Mode"))

                Text(profileDescription)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text(settings.t("Appearance"))
            }

            Section {
                Picker(settings.t("Speech Detail"), selection: $settings.verbosity) {
                    Text(settings.t("Minimal")).tag(Verbosity.minimal)
                    Text(settings.t("Normal")).tag(Verbosity.normal)
                    Text(settings.t("Detailed")).tag(Verbosity.detailed)
                }

                Toggle(settings.t("Haptic-first leveling"), isOn: $settings.hapticFirst)
                    .accessibilityHint(settings.t("Reserve speech for framing; use haptics for leveling."))

                Toggle(settings.t("Auto capture when ready"), isOn: $settings.autoCapture)
                    .accessibilityHint(settings.t("Captures automatically when level, sharp, and framed."))
            } header: {
                Text(settings.t("Guidance"))
            } footer: {
                Text(settings.t("Auto capture waits for a stable ready scene and will not fire repeatedly."))
            }

            Section {
                Label {
                    Text(settings.t("The Fix Photo workflow only rotates, corrects perspective, and crops. It never uses generative AI."))
                } icon: {
                    Image(systemName: "checkmark.shield.fill")
                        .foregroundStyle(.green)
                        .accessibilityHidden(true)
                }
                .font(.footnote)
            } header: {
                Text(settings.t("Authenticity"))
            }
        }
        .navigationTitle(settings.t("Settings"))
    }

    private var profileDescription: String {
        switch settings.interfaceMode {
        case "Blind":
            return settings.t("Blind mode keeps screens concise and relies more on VoiceOver and haptics.")
        case "Low Vision":
            return settings.t("Low Vision mode uses larger text, larger controls, and stronger visual emphasis.")
        default:
            return settings.t("Standard mode balances visual detail with accessibility guidance.")
        }
    }
}
