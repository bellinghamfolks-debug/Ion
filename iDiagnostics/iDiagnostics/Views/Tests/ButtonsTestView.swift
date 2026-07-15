import SwiftUI

/// The `.buttons` diagnostic: detects Volume Up / Volume Down presses by
/// observing the system output volume. The power/side button emits no public
/// event on iOS, so it is shown honestly as `.unsupported`.
struct ButtonsTestView: View {
    @EnvironmentObject private var store: DiagnosticsStore
    @StateObject private var hardware = HardwareService()

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("أزرار الصوت", systemImage: "button.horizontal.top.press")
                            .font(.headline)
                        Text("اضغط زر رفع الصوت ثم زر خفض الصوت. يتم الكشف عبر تتبّع مستوى الصوت.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }

                Card {
                    VStack(spacing: 14) {
                        detectionRow(title: "رفع الصوت",
                                     systemImage: "speaker.wave.3.fill",
                                     detected: hardware.volumeUpDetected,
                                     count: hardware.volumeUpCount)
                        Divider()
                        detectionRow(title: "خفض الصوت",
                                     systemImage: "speaker.wave.1.fill",
                                     detected: hardware.volumeDownDetected,
                                     count: hardware.volumeDownCount)
                    }
                }

                powerButtonNote

                if hardware.volumeUpDetected && hardware.volumeDownDetected {
                    Card {
                        HStack(spacing: 12) {
                            Image(systemName: TestOutcome.pass.systemImage)
                                .foregroundStyle(TestOutcome.pass.color)
                                .accessibilityHidden(true)
                            Text("تم اكتشاف كلا الزرّين بنجاح")
                                .font(.headline)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("تم اكتشاف كلا الزرّين بنجاح")
                }

                Button {
                    hardware.resetVolumeDetection()
                } label: {
                    Label("إعادة الكشف", systemImage: "arrow.counterclockwise")
                        .frame(maxWidth: .infinity, minHeight: 30)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            .padding(Theme.screenPadding)
        }
        .navigationTitle(TestCategory.buttons.titleAr)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { hardware.startVolumeMonitoring() }
        .onDisappear { hardware.stopVolumeMonitoring() }
        .onChange(of: bothDetected) { newValue in
            if newValue { recordPass() }
        }
    }

    private var bothDetected: Bool {
        hardware.volumeUpDetected && hardware.volumeDownDetected
    }

    private func detectionRow(title: String,
                              systemImage: String,
                              detected: Bool,
                              count: Int) -> some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(detected ? Color.green : .secondary)
                .accessibilityHidden(true)
            Text(title).font(.headline)
            Spacer()
            HStack(spacing: 6) {
                Image(systemName: detected ? "checkmark.circle.fill" : "circle.dashed")
                    .foregroundStyle(detected ? Color.green : .secondary)
                Text(detected ? "تم الكشف (\(count))" : "بانتظار الضغط")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(detected ? Color.green : .secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("زر \(title)")
        .accessibilityValue(detected ? "تم الكشف، عدد الضغطات \(count)" : "بانتظار الضغط")
    }

    private var powerButtonNote: some View {
        Card {
            HStack(spacing: 14) {
                Image(systemName: TestOutcome.unsupported.systemImage)
                    .font(.title)
                    .foregroundStyle(TestOutcome.unsupported.color)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Label("زر الطاقة / الزر الجانبي", systemImage: "power")
                        .font(.headline)
                    Text("لا توفّر iOS أي واجهة عامة للكشف عن ضغط زر الطاقة")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(TestOutcome.unsupported.titleAr)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(TestOutcome.unsupported.color)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("زر الطاقة، \(TestOutcome.unsupported.titleAr). لا توفّر iOS أي واجهة عامة للكشف عن ضغط زر الطاقة")
    }

    private func recordPass() {
        let result = TestResult(
            category: .buttons,
            outcome: .pass,
            summaryAr: "تم اكتشاف زرّي رفع وخفض الصوت بنجاح",
            metrics: [
                .init(label: "رفع الصوت", value: "\(hardware.volumeUpCount) ضغطة"),
                .init(label: "خفض الصوت", value: "\(hardware.volumeDownCount) ضغطة"),
                .init(label: "زر الطاقة", value: TestOutcome.unsupported.titleAr)
            ]
        )
        store.record(result)
    }
}
