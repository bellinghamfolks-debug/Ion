import SwiftUI
import UIKit

/// Version 3 accessibility: vibration-only feedback, braille-friendly
/// wording, the speaking voice, how much is said, shake for status, the
/// giant brewing screen, magic tap, progress ticks and drip wait.
struct AccessibilityPlusView: View {
    @Environment(AppModel.self) var model
    @State var voices: [SpeechVoices.Voice] = []

    var body: some View {
        ProForm(title: L("screen.accessibility3"), help: .settings) {
            Section {
                Toggle(L("a11y.hapticOnly"), isOn: model.binding(\.hapticOnly))
                if model.settings.hapticOnly {
                    ForEach(HapticPatterns.Pattern.allCases) { pattern in
                        Button { HapticPatterns.play(pattern) } label: { Label(pattern.title, systemImage: "iphone.radiowaves.left.and.right") }
                            .accessibilityHint(L("a11y.haptic.try"))
                    }
                }
            } footer: { Text(L("a11y.hapticOnly.footer")) }

            Section {
                Toggle(L("a11y.braille"), isOn: model.binding(\.brailleBrief))
                Picker(L("a11y.verbosity"), selection: model.binding(\.verbosity)) {
                    Text(L("a11y.verbosity.0")).tag(0)
                    Text(L("a11y.verbosity.1")).tag(1)
                    Text(L("a11y.verbosity.2")).tag(2)
                }
            } footer: { Text(L("a11y.braille.footer")) }

            Section {
                Picker(L("a11y.voice"), selection: model.binding(\.speechVoiceID)) {
                    Text(L("a11y.voice.default")).tag("")
                    ForEach(voices) { voice in Text(voice.name).tag(voice.id) }
                }
                VStack(alignment: .leading) {
                    Text(L("a11y.rate"))
                    Slider(value: model.binding(\.speechRate), in: 0...1, step: 0.05)
                        .accessibilityValue(L("unit.percent", Int(model.settings.speechRate * 100)))
                }
                Button(L("a11y.voice.preview")) { Announcer.shared.speak(L("a11y.voice.sample")) }
            } header: { Text(L("a11y.voice.header")) } footer: { Text(L("a11y.voice.footer")) }

            Section {
                Toggle(L("a11y.shake"), isOn: model.binding(\.shakeForStatus))
                Toggle(L("a11y.giant"), isOn: model.binding(\.giantBrewing))
                Toggle(L("a11y.magicTap"), isOn: model.binding(\.magicTapUsual))
                Toggle(L("a11y.ticks"), isOn: model.binding(\.progressTicks))
                Toggle(L("a11y.dripWait"), isOn: model.binding(\.dripWait))
            } footer: { Text(L("a11y.gestures.footer")) }

            Section {
                NavigationLink { VoiceOverPracticeView() } label: { Label(L("screen.voPractice"), systemImage: "hand.tap") }
            }
        }
        .onAppear { voices = SpeechVoices.available() }
    }
}

/// Practise the VoiceOver gestures the app uses, with feedback for each.
struct VoiceOverPracticeView: View {
    enum Lesson: Int, CaseIterable { case doubleTap, adjust, magicTap, escape, actions }

    @Environment(\.dismiss) var dismiss
    @State var lesson: Lesson = .doubleTap
    @State var value = 3
    @State var done: Set<Lesson> = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(L("vo.intro")).font(.body).foregroundStyle(Theme.textSecondary)
                Text(L("vo.lesson.\(lesson.rawValue).title"))
                    .font(.display(.title2, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                Text(L("vo.lesson.\(lesson.rawValue).body")).font(.title3)
                practice
                ProgressView(value: Double(done.count), total: Double(Lesson.allCases.count))
                    .tint(Theme.accent)
                    .accessibilityLabel(L("vo.progress"))
                    .accessibilityValue(L("vo.progress.value", done.count, Lesson.allCases.count))
                if done.count == Lesson.allCases.count {
                    Text(L("vo.allDone")).font(.headline).foregroundStyle(Theme.success)
                }
            }
            .padding(20)
        }
        .screenBackground()
        .navigationTitle(L("screen.voPractice"))
        .accessibilityAction(.magicTap) { if lesson == .magicTap { pass() } }
        .accessibilityAction(.escape) {
            if lesson == .escape { pass() } else { dismiss() }
        }
    }

    @ViewBuilder
    private var practice: some View {
        switch lesson {
        case .doubleTap:
            Button(L("vo.lesson.0.button")) { pass() }.buttonStyle(PrimaryButtonStyle())
        case .adjust:
            Text(L("vo.strength", value))
                .font(.title.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 80)
                .card()
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(L("param.aroma"))
                .accessibilityValue("\(value)")
                .accessibilityAdjustableAction { direction in
                    value = direction == .increment ? min(5, value + 1) : max(1, value - 1)
                    if value == 5 { pass() }
                }
        case .magicTap, .escape:
            Text(L("vo.lesson.\(lesson.rawValue).try"))
                .frame(maxWidth: .infinity, minHeight: 80)
                .card()
        case .actions:
            Text(L("vo.lesson.4.item"))
                .frame(maxWidth: .infinity, minHeight: 80)
                .card()
                .accessibilityElement(children: .combine)
                .accessibilityAction(named: Text(L("vo.lesson.4.action"))) { pass() }
        }
    }

    private func pass() {
        done.insert(lesson)
        Announcer.shared.success()
        UIAccessibility.post(notification: .announcement, argument: L("vo.passed"))
        if let next = Lesson(rawValue: lesson.rawValue + 1) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { lesson = next }
        }
    }
}

/// While a drink is made: the phase and percentage as large as the screen
/// allows, in high contrast, with a full-width stop button.
struct GiantBrewingPanel: View {
    let session: BrewSession
    let stop: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Text(session.activity == .idle ? session.recipe.displayName : session.activity.title)
                .font(.system(size: 44, weight: .heavy, design: .rounded))
                .minimumScaleFactor(0.5)
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text(L("unit.percent", Int(session.progress * 100)))
                .font(.system(size: 120, weight: .black, design: .rounded).monospacedDigit())
                .minimumScaleFactor(0.4)
                .foregroundStyle(Theme.accent)
                .accessibilityLabel(L("brew.progress"))
                .accessibilityValue(L("unit.percent", Int(session.progress * 100)))
                .accessibilityAddTraits(.updatesFrequently)
            Button(role: .destructive, action: stop) {
                Label(L("action.stop"), systemImage: "stop.fill")
                    .font(.system(size: 34, weight: .bold))
                    .frame(maxWidth: .infinity, minHeight: 120)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.danger)
            .accessibilityInputLabels([L("action.stop"), L("voice.stop")])
        }
    }
}
