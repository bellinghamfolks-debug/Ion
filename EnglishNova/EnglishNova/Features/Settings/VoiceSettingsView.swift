import SwiftUI

/// Choose the English voice used everywhere in the app. iOS ships compact
/// voices; the enhanced and premium ones sound far more natural and are a
/// free download in iOS Settings.
struct VoiceSettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var textToSpeech: TextToSpeechService
    @State private var refresh = UUID()

    private var language: String { settings.accentVariant.localeIdentifier }

    var body: some View {
        List {
            Section {
                Picker(L("اللكنة"), selection: $settings.accentVariant) {
                    ForEach(AccentVariant.allCases) { accent in
                        Text("\(accent.titleAr) • \(accent.titleEn)").tag(accent)
                    }
                }
            }

            if TextToSpeechService.hasOnlyBasicVoices(for: language) {
                Section {
                    Label(LE("الأصوات المثبّتة أساسية فقط", "Only basic voices are installed"), systemImage: "exclamationmark.circle.fill")
                        .font(.headline)
                        .foregroundStyle(AppTheme.warning)
                    Text(downloadSteps)
                        .font(.subheadline)
                }
            }

            Section {
                let options = TextToSpeechService.voices(for: language)
                let chosen = UserDefaults.standard.string(forKey: TextToSpeechService.preferenceKey(for: language))
                Button {
                    textToSpeech.choose(nil, for: language)
                    refresh = UUID()
                } label: {
                    row(title: LE("تلقائي: أفضل صوت متاح", "Automatic: best available voice"), detail: nil, selected: chosen == nil)
                }
                ForEach(options) { option in
                    Button {
                        textToSpeech.choose(option, for: language)
                        refresh = UUID()
                        textToSpeech.speak(sample, language: language, rate: Float(settings.speechRate))
                    } label: {
                        row(title: option.name, detail: qualityTitle(option), selected: chosen == option.id)
                    }
                }
            } header: {
                Text(LE("الصوت", "Voice"))
            } footer: {
                Text(LE("اختر صوتًا لتسمعه مباشرة. الأصوات المحسّنة والمميزة أوضح وأقرب للنطق الطبيعي.",
                        "Pick a voice to hear it. Enhanced and premium voices are clearer and more natural."))
            }
            .id(refresh)

            Section(LE("السرعة", "Speed")) {
                Slider(value: $settings.speechRate, in: 0.3...0.58) {
                    Text(L("سرعة النطق"))
                } minimumValueLabel: {
                    Image(systemName: "tortoise.fill").accessibilityHidden(true)
                } maximumValueLabel: {
                    Image(systemName: "hare.fill").accessibilityHidden(true)
                }
                .accessibilityValue(LfE("%@ بالمئة", "%@ percent", "\(Int((settings.speechRate / 0.58) * 100))"))
                Button {
                    textToSpeech.speak(sample, language: language, rate: Float(settings.speechRate))
                } label: {
                    Label(LE("استمع إلى عيّنة", "Play a sample"), systemImage: "play.circle.fill")
                }
            }
        }
        .navigationTitle(LE("الأصوات", "Voices"))
    }

    private var sample: String { "Hello! This is how English lessons will sound in EnglishNova." }

    private var downloadSteps: String {
        LE("لتنزيل صوت طبيعي مجانًا: افتح «الإعدادات» ثم «تسهيلات الاستخدام» ثم «المحتوى المنطوق» ثم «الأصوات» ثم «الإنجليزية»، واختر صوتًا مكتوبًا بجانبه «محسّن» أو «مميز». ارجع بعدها إلى هذه الشاشة.",
           "To download a natural voice for free: open Settings › Accessibility › Spoken Content › Voices › English and pick a voice marked Enhanced or Premium. Then come back to this screen.")
    }

    private func qualityTitle(_ option: TextToSpeechService.VoiceOption) -> String {
        switch option.qualityRank {
        case 3: return LE("مميز", "Premium")
        case 2: return LE("محسّن", "Enhanced")
        default: return LE("أساسي", "Basic")
        }
    }

    private func row(title: String, detail: String?, selected: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).foregroundStyle(.primary)
                if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            if selected {
                Image(systemName: "checkmark").foregroundStyle(AppTheme.brand).accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}
