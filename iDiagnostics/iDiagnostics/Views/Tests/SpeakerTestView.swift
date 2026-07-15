import SwiftUI

/// Speaker test: plays a clear sine-wave tone through the loud speaker, then asks
/// the user whether they heard it. Records `.speaker`.
struct SpeakerTestView: View {
    @EnvironmentObject private var store: DiagnosticsStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var speaker = SpeakerController()

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                instructionsCard
                playButton
                Text("هل سمعت النغمة؟")
                    .font(.headline)
                PassFailControls(onPass: { record(.pass) },
                                 onFail: { record(.fail) })
            }
            .padding(Theme.screenPadding)
            .animation(.easeInOut(duration: 0.3), value: speaker.isPlaying)
        }
        .navigationTitle(TestCategory.speaker.titleAr)
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { speaker.stop() }
    }

    // MARK: Sections

    private var instructionsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Label("طريقة الفحص", systemImage: "info.circle.fill")
                    .font(.headline)
                Text("اضغط على الزر لتشغيل نغمة اختبار واضحة عبر مكبّر الصوت. تأكّد من رفع مستوى الصوت.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text("ملاحظة: لا تتيح واجهات iOS العامة اختيار المكبّر العلوي أو السفلي بشكل منفصل؛ يُختبر مكبّر الصوت كما يوجّهه النظام.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var playButton: some View {
        Button {
            speaker.playTestTone()
        } label: {
            VStack(spacing: 10) {
                Image(systemName: speaker.isPlaying ? "speaker.wave.3.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 46))
                    .symbolEffectPulseIfAvailable(active: speaker.isPlaying)
                Text(speaker.isPlaying ? "جارٍ التشغيل…" : "تشغيل نغمة الاختبار")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity, minHeight: 150)
            .foregroundStyle(.white)
            .background(speaker.isPlaying ? Color.blue : Color.accentColor,
                        in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
        }
        .buttonStyle(.plain)
        .disabled(speaker.isPlaying)
        .accessibilityLabel("تشغيل نغمة الاختبار")
        .accessibilityHint("يشغّل نغمة عبر مكبّر الصوت الرئيسي")
    }

    // MARK: Recording

    private func record(_ outcome: TestOutcome) {
        let result = TestResult(
            category: .speaker,
            outcome: outcome,
            summaryAr: outcome == .pass
                ? "سُمعت نغمة الاختبار بوضوح عبر مكبّر الصوت."
                : "أبلغ المستخدم عن عدم سماع النغمة أو تشوّهها.",
            metrics: [
                .init(label: "نوع الإشارة", value: "نغمة جيبية 660 هرتز"),
                .init(label: "التوجيه", value: "مكبّر الصوت الرئيسي (النظام)")
            ])
        store.record(result)
        speaker.stop()
        dismiss()
    }
}

private extension View {
    /// Uses the iOS 17 pulse symbol effect where available, no-op on iOS 16.
    @ViewBuilder
    func symbolEffectPulseIfAvailable(active: Bool) -> some View {
        if #available(iOS 17.0, *) {
            self.symbolEffect(.pulse, isActive: active)
        } else {
            self
        }
    }
}
