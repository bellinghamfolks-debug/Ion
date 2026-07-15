import SwiftUI

/// Microphone test: records ~3 seconds, plays it straight back, then asks the
/// user whether they heard themselves clearly. Records `.microphone`.
struct MicrophoneTestView: View {
    @EnvironmentObject private var store: DiagnosticsStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var mic = MicrophoneController()

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if mic.permission == .denied {
                    PermissionDeniedCard(
                        systemImage: "mic.slash.fill",
                        message: "لا يمكن الوصول إلى الميكروفون. فعّل إذن الميكروفون من الإعدادات لإجراء الفحص.")
                } else {
                    instructionsCard
                    recordButton
                    if mic.phase == .finished {
                        Text("هل سمعت صوتك بوضوح؟")
                            .font(.headline)
                            .transition(.opacity)
                        PassFailControls(onPass: { record(.pass) },
                                         onFail: { record(.fail) })
                    }
                }
            }
            .padding(Theme.screenPadding)
            .animation(.easeInOut(duration: 0.3), value: mic.phase)
        }
        .navigationTitle(TestCategory.microphone.titleAr)
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { mic.cancel() }
    }

    // MARK: Sections

    private var instructionsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Label("طريقة الفحص", systemImage: "info.circle.fill")
                    .font(.headline)
                Text("اضغط على الزر ثم تحدّث لمدة ثلاث ثوانٍ. سيُعاد تشغيل التسجيل تلقائيًا لتسمع صوتك.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text("ملاحظة: يختار النظام الميكروفون المستخدم (الأساسي أو الثانوي)، ولا يمكن عزل ميكروفون محدد عبر واجهات iOS العامة.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var recordButton: some View {
        VStack(spacing: 12) {
            Button {
                mic.recordThenPlay()
            } label: {
                VStack(spacing: 10) {
                    Image(systemName: iconName)
                        .font(.system(size: 46))
                        .scaleEffect(mic.phase == .recording ? 1.0 + Double(mic.level) * 0.3 : 1.0)
                        .animation(.easeInOut(duration: 0.1), value: mic.level)
                    Text(buttonTitle)
                        .font(.headline)
                }
                .frame(maxWidth: .infinity, minHeight: 150)
                .foregroundStyle(.white)
                .background(buttonColor, in: RoundedRectangle(cornerRadius: Theme.cornerRadius))
            }
            .buttonStyle(.plain)
            .disabled(mic.phase == .recording || mic.phase == .playing)
            .accessibilityLabel(buttonTitle)
            .accessibilityHint("يسجّل ثلاث ثوانٍ من الصوت ثم يعيد تشغيله")

            if mic.phase == .recording || mic.phase == .playing {
                Text(mic.phase == .recording ? "جارٍ التسجيل…" : "جارٍ التشغيل…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(false)
            }
        }
    }

    // MARK: Derived UI

    private var iconName: String {
        switch mic.phase {
        case .recording: return "waveform"
        case .playing:   return "speaker.wave.2.fill"
        default:         return "mic.fill"
        }
    }

    private var buttonTitle: String {
        switch mic.phase {
        case .recording: return "جارٍ التسجيل…"
        case .playing:   return "جارٍ التشغيل…"
        case .finished:  return "سجّل 3 ثوانٍ مرة أخرى"
        case .idle:      return "سجّل 3 ثوانٍ"
        }
    }

    private var buttonColor: Color {
        switch mic.phase {
        case .recording: return .red
        case .playing:   return .blue
        default:         return .accentColor
        }
    }

    // MARK: Recording

    private func record(_ outcome: TestOutcome) {
        let result = TestResult(
            category: .microphone,
            outcome: outcome,
            summaryAr: outcome == .pass
                ? "تم التسجيل والتشغيل بوضوح."
                : "أبلغ المستخدم عن صوت غير واضح أو غير مسموع.",
            metrics: [
                .init(label: "مدة التسجيل", value: "3 ثوانٍ"),
                .init(label: "اختيار الميكروفون", value: "يديره النظام تلقائيًا")
            ])
        store.record(result)
        mic.cancel()
        dismiss()
    }
}
