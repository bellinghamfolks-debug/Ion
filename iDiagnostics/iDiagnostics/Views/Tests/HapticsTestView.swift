import SwiftUI

/// The `.haptics` diagnostic: plays graduated haptic patterns then lets the user
/// self-assess whether the taptic engine responded.
struct HapticsTestView: View {
    @EnvironmentObject private var store: DiagnosticsStore
    @StateObject private var hardware = HardwareService()

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("محرّك الاهتزاز", systemImage: "iphone.radiowaves.left.and.right")
                            .font(.headline)
                        Text(hardware.supportsHaptics
                             ? "المس كل نمط واشعر بالاهتزاز المقابل"
                             : "لا يدعم هذا الجهاز Core Haptics؛ سيتم استخدام اهتزاز النظام البديل")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }

                Card {
                    VStack(spacing: 12) {
                        patternButton("اهتزاز خفيف", "الخفيف", "wave.3.left") { hardware.playLight() }
                        patternButton("اهتزاز متوسط", "المتوسط", "wave.3.left.circle") { hardware.playMedium() }
                        patternButton("اهتزاز قوي", "القوي", "wave.3.left.circle.fill") { hardware.playHeavy() }
                        patternButton("نمط النجاح", "النجاح", "checkmark.seal.fill") { hardware.playSuccess() }
                    }
                }

                Card {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("هل شعرت بالاهتزازات؟").font(.headline)
                        PassFailControls(
                            onPass: { record(.pass) },
                            onFail: { record(.fail) }
                        )
                    }
                }
            }
            .padding(Theme.screenPadding)
        }
        .navigationTitle(TestCategory.haptics.titleAr)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { hardware.prepareHaptics() }
    }

    private func patternButton(_ title: String,
                               _ shortName: String,
                               _ systemImage: String,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: systemImage)
                Text(title).fontWeight(.semibold)
                Spacer()
                Image(systemName: "hand.tap")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, minHeight: 30)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .accessibilityLabel("تشغيل \(title)")
        .accessibilityHint("سيهتز الجهاز بالنمط \(shortName)")
    }

    private func record(_ outcome: TestOutcome) {
        let result = TestResult(
            category: .haptics,
            outcome: outcome,
            summaryAr: outcome == .pass
                ? "أكّد المستخدم الشعور باهتزازات محرّك الاهتزاز"
                : "لم يشعر المستخدم باهتزاز محرّك الاهتزاز",
            metrics: [
                .init(label: "دعم Core Haptics", value: hardware.supportsHaptics ? "نعم" : "لا")
            ]
        )
        store.record(result)
    }
}
