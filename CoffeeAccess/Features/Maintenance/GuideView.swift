import SwiftUI

/// A maintenance guide, one step at a time. When the step changes, VoiceOver
/// focus moves to the new step so it is read straight away. "All steps"
/// shows the whole guide as a list for reading ahead.
struct GuideView: View {
    @Environment(AppModel.self) var model
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
                if guide == .descaling {
                    NavigationLink { DescaleRunView() } label: {
                        NavigationRowCard(title: L("descale.run.title"), subtitle: L("descale.run.subtitle"), symbol: "timer")
                    }
                    .buttonStyle(.plain)
                }
                if guide == .waterHardness {
                    NavigationLink { HardnessTestView() } label: {
                        NavigationRowCard(title: L("hardness.title"), subtitle: L("hardness.subtitle"), symbol: "testtube.2")
                    }
                    .buttonStyle(.plain)
                }
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

            if let minutes = guide.stepTimers[step + 1] {
                StepTimer(minutes: minutes, label: guide.steps[step])
            }

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
                        if let task = CareTask(guide: guide) { model.logCare(task) }
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

/// A countdown for a step that involves waiting (soaking, drying, rinsing),
/// spoken each minute and ending with a sound even when the phone is locked.
struct StepTimer: View {
    let minutes: Int
    let label: String
    @State var remaining: Int?
    @State var task: Task<Void, Never>?

    var body: some View {
        Group {
            if let remaining {
                HStack {
                    Text(String(format: "%d:%02d", remaining / 60, remaining % 60))
                        .font(.title2.monospacedDigit().weight(.semibold))
                        .accessibilityAddTraits(.updatesFrequently)
                    Spacer()
                    Button(L("tea.stop"), role: .destructive) { stop() }.buttonStyle(.bordered)
                }
            } else {
                Button { start() } label: { Label(L("stepTimer.start", minutes), systemImage: "timer") }
                    .buttonStyle(SecondaryButtonStyle())
            }
        }
        .onDisappear { stop() }
    }

    private func start() {
        let total = minutes * 60
        remaining = total
        Announcer.shared.announce(L("stepTimer.started", minutes))
        NotificationManager.shared.scheduleTimer(id: "step", title: L("stepTimer.done"), body: label, seconds: total)
        task = Task { @MainActor in
            for left in stride(from: total - 1, through: 0, by: -1) {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
                remaining = left
                if left > 0, left % 60 == 0 { Announcer.shared.announce(L("tea.minutesLeft", left / 60)) }
            }
            remaining = nil
            Announcer.shared.success()
            Announcer.shared.announce(L("stepTimer.done"), priority: .high)
        }
    }

    private func stop() {
        task?.cancel()
        task = nil
        remaining = nil
        NotificationManager.shared.cancelTimer(id: "step")
    }
}
