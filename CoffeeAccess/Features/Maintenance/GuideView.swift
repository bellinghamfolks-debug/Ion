import SwiftUI

/// A maintenance guide, one step at a time. When the step changes, VoiceOver
/// focus moves to the new step so it is read straight away. "All steps"
/// shows the whole guide as a list for reading ahead.
struct GuideView: View {
    let guide: MaintenanceGuideID
    @State var step = 0
    @State var showAll = false
    @AccessibilityFocusState var stepFocused: Bool

    init(guide: MaintenanceGuideID) {
        self.guide = guide
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(guide.intro)
                    .font(.body)
                    .foregroundStyle(Theme.textSecondary)
                Picker(L("guide.mode"), selection: $showAll) {
                    Text(L("guide.mode.steps")).tag(false)
                    Text(L("guide.mode.all")).tag(true)
                }
                .pickerStyle(.segmented)
                if showAll { allSteps } else { singleStep }
            }
            .padding(16)
        }
        .screenBackground()
        .navigationTitle(guide.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var singleStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                Text(L("guide.stepOf", step + 1, guide.stepCount))
                    .font(.headline)
                    .foregroundStyle(Theme.accent)
                Text(guide.steps[step])
                    .font(.title3)
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
            .accessibilityElement(children: .combine)
            .accessibilityFocused($stepFocused)

            ProgressView(value: Double(step + 1), total: Double(guide.stepCount))
                .tint(Theme.accent)
                .accessibilityHidden(true)

            HStack(spacing: 12) {
                Button(L("guide.previous")) { move(-1) }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(step == 0)
                if step < guide.stepCount - 1 {
                    Button(L("guide.next")) { move(1) }
                        .buttonStyle(PrimaryButtonStyle())
                } else {
                    Button(L("guide.finish")) {
                        Announcer.shared.success()
                        Announcer.shared.announce(L("guide.finished", guide.title))
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
            }
        }
    }

    private var allSteps: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(guide.steps.enumerated()), id: \.offset) { index, text in
                HStack(alignment: .top, spacing: 12) {
                    Text("\(index + 1)")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(Theme.onAccent)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Theme.accent))
                        .accessibilityHidden(true)
                    Text(text)
                        .font(.body)
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()
                .accessibilityElement(children: .combine)
                .accessibilityLabel(L("guide.stepOf", index + 1, guide.stepCount))
                .accessibilityValue(text)
            }
        }
    }

    private func move(_ delta: Int) {
        step = max(0, min(guide.stepCount - 1, step + delta))
        Announcer.shared.tick()
        stepFocused = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { stepFocused = true }
    }
}
